module flow.flow.process;

import core.thread, core.sync.rwmutex;
import std.range.interfaces, std.string;

import flow.flow.exception, flow.flow.type, flow.flow.data;
import flow.flow.entity;
import flow.base.dev, flow.base.interfaces, flow.base.data;

/// a hull hosting an entity
class Hull {
    private ReadWriteMutex _lock;
    private Flow _flow;
    private Entity _entity;
    private List!EntityInfo _children;

    @property EntityInfo info() { return this._entity.meta.info; } 
    @property string address() { return this.info.ptr.id~"@"~this.info.ptr.domain; }
    @property FlowPtr flow() { return this._flow.ptr; }
    @property bool tracing() { return this._flow.tracing; }

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    this(Flow f, string id, EntityMeta m) {
        this._flow = f;
        this.create(id, m);
        this.resume();
    }

    private void createChildren() {
        foreach(EntityMeta m; this.entity.meta.children)
            this.children.add(this._flow.add(m));
    }

    private void disposeChildren() {
        foreach(EntityInfo i; this._children.clone()) {
            this._flow.remove(i);
            this._children.remove(i);
        } 
    }

    private void suspendChildren() {
        foreach(i; this._owned) {
            auto e = this.get(i);
            if(e !is null)
                e.hull.suspend();
        }
    }

    void create(EntityMeta m) {
        m.info.ptr.flow = this.flow;
        auto e = Entity.create(m, this);
        try {
            this.createChildren();
        } catch(Exception ex) {
            e.dispose();
            throw(ex);
        }
    } 

    void suspend() {
        synchronized(this.lock.writer) {
            this._isSuspended = true;
            this.suspendChildren();            
        } 
    } 
    
    void resume() {
        synchronized(this.lock.writer) {
            this.resumeChildren();
            this.entity.resume();

            this._isSuspended = false;
        }

        // resume inboud signals
        foreach(s; this.entity.meta.inbound.clone()) {
            this.receive(s);
            synchronized(this.lock.writer)
                this.entity.meta.inboud.remove(s);
        }
    }

    private void resumeChildren()
    {
        foreach(i; this._owned) {
            auto e = this.get(i);
            if(e !is null)
                e.hull.resume();
        }
    }

    EntityMeta snap()
    {
        synchronized(this.lock.writer) {
            auto l = List!EntityMeta;
            auto m = new EntityMeta;
            m.children.add(this.snapChildren());
            l.add(m);
            return l;
        } 
    }
    
    private List!EntityMeta snapChildren() {
        auto l = List!EntityMeta;
        foreach(i; this._owned)
        {
            auto e = this.get(i);
            if(e !is null)
            {
                auto m = new EntityMeta;
                m.info = i;
                m.context = e.context;
                l.add(e.hull.snap());
            } 
        }
        return l;
    }

    void spawn(EntityInfo i, Data c) {
        synchronized(this.lock.writer)
        {
            auto e = Entity.create(i, c);
            this._owned.add(this.flow.add(e));
        } 
    }

    
    void beginListen(string s, string t) {
        synchronized(this.lock.writer) {
            auto l = new ListeningMeta;
            l.signal = s;
            l.tick = t;

            auto found = false;
            foreach(ml; this.entity.meta.listenings) {
                found = l.signal == ml.signal && l.tick == ml.tick;
                if(found) break;
            }

            if(!found)
                this.entity.meta.listenings.add(l);
        }
    }
    
    void endListen(string s, string t) {
        synchronized(this.lock.writer) {
            ListeningMeta finding = null;
            foreach(ml; this.entity.meta.listenings) {
                if(s == ml.signal && t == ml.tick)
                    finding = ml;
                if(finding !is null) break;
            }

            if(finding !is null)
                this.entity.meta.listenings.remove(finding);
        }
    }

    IEntity get(EntityInfo i) { return this.flow.get(i); }
    
    bool receive(Signal s) {
        if(!this._isStopped) {
            this.writeDebug("{RECEIVE} signal("~s.type~", "~s.id.toString~")", 2);
            
            // search for listenings and start all registered for given signal type
            auto accepted = false;
            synchronized(this.lock.reader) {
                foreach(l; this.entity.meta.listenings)
                    if(l.signal == s.type) {
                        if(!this._isSuspended) {
                            this.entity.createTicker(s, l.tick);
                            accepted = true;
                        } else if(s.as!Anycast is null) { // anycasts cannot be received anymore, all other signals are stored in meta
                            this.entity.meta.inboud.add(s);
                            accepted = true;
                            break;
                        }
                    }
            }
                
            return accepted;
        } else return false;
    }
    
    bool send(Unicast s, EntityPtr e) {
        synchronized(this.lock.reader) {
            if(this.flow._config.preventIdTheft) {
                static if(is(T == Entity))
                    s.source = this.obj.info.ptr;
                else
                    s.source = null;
            }

            return this.flow.send(s, e);
        }
    }
    bool send(Unicast s, EntityInfo e) { return this.send(s, e.ptr); }
    bool send(Unicast s, IEntity e) { return this.send(s, e.info); }
    bool send(Unicast s) {
        this._preventIdTheft(s);
        return this.flow.send(s);
    }
    bool send(Multicast s) {
        this._preventIdTheft(s);
        return this.flow.send(s);
    }
    bool send(Anycast s) {
        this._preventIdTheft(s);
        return this.flow.send(s);
    }

    // wait for finish
    void wait(bool delegate() expr) { this.flow.wait(expr); }

    private void _preventIdTheft(Signal s) {
        if(this.flow.config.preventIdTheft)
        {
            static if(is(T == Entity))
                s.source = this.obj.info.ptr;
            else
                s.source = null;
        }
    }

    void dispose() { this.entity.dispose(); }
}

/// a flow process able to host the local swarm
class Flow : IFlow
{
    private FlowConfig _config;
    private bool _shouldStop;
    private bool _isStopped;
    private Mutex _lock;
    private Hull!Entity[string] _local;

    private FlowPtr _ptr;
    @property FlowPtr ptr() { return this._ptr; }

    @property bool tracing(){ return this._config.tracing; }

    this(FlowConfig c = null)
    {
        if(c is null) // if no config is passed use defaults
        {
            c = new FlowConfig;
            c.tracing = false;
            c.preventIdTheft = true;
        }

        this._lock = new Mutex;
        this._config = c;
        auto pf = new FlowPtr;
        pf.ptress = "";
        this._ptr = pf;
    }

    ~this()
    {
        this.stop();
    }

    void stop()
    {
        if(!this._shouldStop)
        {
            this._shouldStop = true;

            this.writeDebug("{DESTROY}", 2);            

            synchronized(this._lock)
                foreach(r, e; this._local)
                    e.dispose();

            this._isStopped = true;
        }
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("process();"~msg, level);
    }

    string add(EntityMeta m)
    {
        auto id = "";
        if(!this._shouldStop)
        {
            if(m is null)
                throw new ParameterException();

            if(!Entity.canCreate(m.info.ptr.type))
                throw new UnsupportedObjectTypeException(m.info.ptr.type);
            
            synchronized(this._lock)
            {
                auto h = new Hull(this, m);
                this.writeDebug("{ADD} entity("~h.info.ptr.type~", "~h.address~")", 2);

                try
                {
                    this._local[id] = m;
                }
                catch(Exception exc)
                {
                    this.writeDebug("{ADD FAILED} entity("~fqnOf(e)~", "~e.id.toString~") ["~exc.msg~"]", 0);
                    if(id in this._local)
                        this._local.remove(id);
                }
            }
        }

        return id;
    }

    string remove(EntityInfo i)
    {
        auto id = "";
        if(!this._shouldStop)
        {
            id = i.prt.name~"@"~i.ptr.domain; 
            synchronized(this._lock)
            {                
                auto m = this._local[i.id];
                this.writeDebug("{REMOVE} entity("~fqnOf(m.obj)~", "~id.toString~")", 2);
                m.dispose();
                this._local.remove(i.id);
            }
        }
        return id;
    }

    IEntity get(EntityInfo i)
    {
        if(!this._shouldStop)
            synchronized(this._lock)
                return this._local[i.id].obj;
        
        return null;
    }

    void wait(bool delegate() expr)
    {
        if(!this._shouldStop)
        {
            while(!expr())
                Thread.sleep(WAITINGTIME);
        }
    }

    private void giveIdAndTypeIfHasnt(Signal s)
    {
        if(s.id == UUID.init)
            s.id = randomUUID;

        if(s.type is null || s.type == "")
            s.type = s.dataType;
    }

    bool send(Unicast s, EntityPtr e)
    {
        s.destination = e;
        return this.send(s);
    }

    bool send(Unicast s, EntityInfo e)
    {
        return this.send(s, e.ptr);
    }

    bool send(Unicast s, IEntity e)
    {
        return this.send(s, e.info.ptr);
    }

    bool send(Unicast s)
    {
        if(!this._shouldStop)
        {
            auto d = s.destination;
            if(d !is null)
            {
                this.giveIdAndTypeIfHasnt(s);
                
                // sending only to acceptable
                foreach(r; this.getReceiver(s.type))
                {
                    auto acceptable = r.ptr.id == d.id;
                    if(acceptable)
                        return this.deliver(s, r.ptr);
                }
            }
        }

        return false;
    }

    bool send(Multicast s)
    {
        if(!this._shouldStop)
        {
            this.giveIdAndTypeIfHasnt(s);
            
            auto found = false;
            // sending only to acceptable
            foreach(r; this.getReceiver(s.type))
            {
                auto acceptable = r.domain.startsWith(s.domain);
                if(acceptable)
                {
                    this.deliver(s, r.ptr);
                    found = true;
                }
            }

            return found;
        }

        return false;
    }

    bool send(Anycast s)
    {
        if(!this._shouldStop)
        {
            this.giveIdAndTypeIfHasnt(s);
            
            auto delivered = false;
            // sending only to acceptable
            foreach(r; this.getReceiver(s.type))
            {
                auto acceptable = r.domain.startsWith(s.domain);
                if(acceptable)
                {
                    delivered = this.deliver(s, r.ptr);
                    if(delivered) break;
                }
            }

            return delivered;
        }

        return false;
    }

    bool deliver(Unicast s, EntityPtr e)
    {
        return this.deliverInternal(s, e);
    }

    void deliver(Multicast s, EntityPtr e)
    {
        this.deliverInternal(s, e);
    }

    bool deliver(Anycast s, EntityPtr e)
    {
        return this.deliverInternal(s, e);
    }

    private bool deliverInternal(Signal s, EntityPtr e)
    {
        if(!this._shouldStop)
        {
            if(e !is null)
                this.writeDebug("{SEND} signal("~s.type~", "~s.id.toString~") TO entity("~ e.id.toString~")", 3);
            else
                this.writeDebug("{SEND} signal("~s.type~", "~s.id.toString~") TO entity(GOD)", 3);

            bool isLocal;
            synchronized(this._lock)
                isLocal = e is null || e.id in this._local;
            if(isLocal)
                return this.receive(s.clone.as!Signal, e);
            else{return false;/* TODO search online when implementing apache thrift*/}
        }

        return false;
    }

    bool receive(Signal s, EntityPtr e)
    {
        if(!this._shouldStop)
        {
            auto stype = s.type;
            if(e !is null)
                this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity("~ e.id.toString~")", 3);
            else
                this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity(GOD)", 3);

            Entity entity;
            synchronized(this._lock)
                if(e !is null && e.id in this._local)
                    entity = this._local[e.id].obj;

            if(entity !is null)
                return entity.receive(s);
            else
                this.writeDebug("{RECEIVE} signal("~s.type~") entity NOT FOUND)", 3);
        }

        return false;
    }
    
    InputRange!EntityInfo getReceiver(string signal)
    {
        return this.getListener(signal).inputRangeObject;
        // TODO when using thrift call InputRange!EntityInfo getReceiver(FlowPtr process, string type) of others and merge results
    }

    EntityInfo[] getListener(string signal)
    {
        if(!this._shouldStop)
        {
            EntityInfo[] found;

            this.writeDebug("{SEARCH} entities FOR signal("~signal~")", 4);

            synchronized(this._lock)
            {
                foreach(id; this._local.keys)
                {
                    auto e = this._local[id].obj.info;
                    foreach(s; e.signals)
                    {
                        if(s == signal)
                        {
                            found ~= e;
                            this.writeDebug("\t!!! entity("~e.ptr.type~", "~e.ptr.id.toString~")", 4);
                            break;
                        }
                    }
                    this.writeDebug("\t>>> entity("~e.ptr.type~", "~e.ptr.id.toString~")", 4);
                }
            }

            return found;
        }

        return null;
    }
}