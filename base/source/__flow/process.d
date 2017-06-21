module __flow.process;

import core.thread, core.sync.rwmutex, std.uuid;
import std.range.interfaces, std.string;

import __flow.exception, __flow.type, __flow.data, __flow.signal;
import __flow.entity;
import flow.base.dev, flow.base.interfaces, flow.base.data;

/// a hull hosting an entity
class Hull {
    private ReadWriteMutex _lock;
    private Flow _flow;
    private Entity _entity;
    private List!EntityInfo _children;

    @property EntityInfo info() { return this._entity.meta.info; } 
    @property string address() { return this.info.ptr.id~"@"~this.info.ptr.domain; }
    @property FlowPtr flowptr() { return this._flow.ptr; }
    @property bool tracing() { return this._flow.config.tracing; }

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    this(Flow f, EntityMeta m) {
        this._flow = f;
        this.initialize(m);
        this.resume();
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("hull("~this.address~");"~msg, level);
    }

    private void createChildren() {
        foreach(EntityMeta m; this._entity.meta.children) {
            auto i = this._flow.add(m);
            if(i !is null)
                this._children.put(i);
        }
    }

    private void disposeChildren() {
        foreach(EntityInfo i; this._children.dup()) {
            this._flow.remove(i);
            this._children.remove(i);
        } 
    }

    private void suspendChildren() {
        foreach(i; this._children) {
            auto h = this._flow.get(i);
            if(h !is null)
                h.suspend();
        }
    }

    void initialize(EntityMeta m) {
        m.info.ptr.flowptr = this.flowptr;
        auto e = Entity.create(m, this);
        try {
            this.createChildren();
        } catch(Exception ex) {
            e.dispose();
            throw(ex);
        }
    } 

    void suspend() {
        synchronized(this._lock.writer) {
            this._isSuspended = true;
            this.suspendChildren();            
        } 
    } 
    
    void resume() {
        synchronized(this._lock.writer) {
            this.resumeChildren();
            this._entity.resume();

            this._isSuspended = false;
        }

        // resume inboud signals
        synchronized(this._lock.writer)
            foreach(s; this._entity.meta.inbound.dup()) {
                this.receive(s);
                this._entity.meta.inbound.remove(s);
            }
    }

    private void resumeChildren()
    {
        foreach(i; this._children) {
            auto h = this._flow.get(i);
            if(h !is null)
                h.resume();
        }
    }

    EntityMeta snap()
    {
        synchronized(this._lock.writer) {
            auto m = this._entity.meta.clone.as!EntityMeta;
            m.children.put(this.snapChildren());
            return m;
        } 
    }
    
    private List!EntityMeta snapChildren() {
        auto l = new List!EntityMeta;
        foreach(i; this._children)
        {
            auto h = this._flow.get(i);
            if(h !is null)
                l.put(h.snap());
        }
        return l;
    }

    bool spawn(EntityMeta m) {
        synchronized(this._lock.writer)
        {
            auto e = Entity.create(m, this);
            auto i = this._flow.add(m);
            if(i !is null) {
                this._children.put(i);
                return true;
            } else return false;
        } 
    }

    
    void beginListen(string s, string t) {
        synchronized(this._lock.writer) {
            auto l = new ListeningMeta;
            l.signal = s;
            l.tick = t;

            auto found = false;
            foreach(ml; this._entity.meta.listenings) {
                found = l.signal == ml.signal && l.tick == ml.tick;
                if(found) break;
            }

            if(!found)
                this._entity.meta.listenings.put(l);
        }
    }
    
    void endListen(string s, string t) {
        synchronized(this._lock.writer) {
            ListeningMeta finding = null;
            foreach(ml; this._entity.meta.listenings) {
                if(s == ml.signal && t == ml.tick)
                    finding = ml;
                if(finding !is null) break;
            }

            if(finding !is null)
                this._entity.meta.listenings.remove(finding);
        }
    }
    
    bool receive(Signal s) {
        this.writeDebug("{RECEIVE} signal("~s.type~", "~s.id.toString~")", 2);
        // search for listenings and start all registered for given signal type
        auto accepted = false;
        synchronized(this._lock.reader) {
            foreach(l; this._entity.meta.listenings)
                if(l.signal == s.type) {
                    if(!this._isSuspended) {
                        this._entity.createTicker(s, l.tick);
                        accepted = true;
                    } else if(s.as!Anycast is null) { // anycasts cannot be received anymore, all other signals are stored in meta
                        this._entity.meta.inbound.put(s);
                        accepted = true;
                        break;
                    }
                }
        }
            
        return accepted;
    }
    
    bool send(Unicast s, EntityPtr e) {
        synchronized(this._lock.reader) {
            if(this._flow.config.preventIdTheft) {
                static if(is(T == Entity))
                    s.source = this.obj.info.ptr;
                else
                    s.source = null;
            }

            return this._flow.send(s, e);
        }
    }
    bool send(Unicast s, EntityInfo e) { return this.send(s, e.ptr); }

    bool send(Unicast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    bool send(Multicast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    bool send(Anycast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }

    private void _preventIdTheft(Signal s) {
        if(this._flow.config.preventIdTheft)
        {
            static if(is(T == Entity))
                s.source = this.obj.info.ptr;
            else
                s.source = null;
        }
    }

    void dispose() { this._entity.dispose(); }
}

/// a flow process able to host the local swarm
class Flow
{
    private bool _shouldStop;
    private bool _isStopped;
    private ReadWriteMutex _lock;
    private Hull[string] _local;

    private FlowPtr _ptr;
    @property FlowPtr ptr() { return this._ptr; }

    private FlowConfig _config;
    @property FlowConfig config(){ return this._config; }

    this(FlowConfig c = null)
    {
        if(c is null) // if no config is passed use defaults
        {
            c = new FlowConfig;
            c.tracing = false;
            c.preventIdTheft = true;
        }

        this._lock = new ReadWriteMutex;
        this._config = c;
        auto pf = new FlowPtr;
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

            synchronized(this._lock.writer)
                foreach(r, e; this._local)
                    e.dispose();

            this._isStopped = true;
        }
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("process();"~msg, level);
    }

    EntityInfo add(EntityMeta m)
    {
        if(!this._shouldStop)
        {
            if(m is null)
                throw new ParameterException("entity meta can't be null");

            if(!Entity.canCreate(m.info.ptr.type))
                throw new UnsupportedObjectTypeException(m.info.ptr.type);
            
            synchronized(this._lock.writer)
            {
                Hull h;
                try
                {
                    h = new Hull(this, m);
                    this.writeDebug("{ADD} entity("~h.info.ptr.type~"|"~h.address~")", 2);
                    this._local[h.address] = h;
                }
                catch(Exception exc)
                {
                    this.writeDebug("{ADD FAILED} entity("~m.info.ptr.type~"|"~m.info.ptr.id~"@"~m.info.ptr.domain~") ["~exc.msg~"]", 0);
                    if(h !is null && h.address in this._local)
                        this._local.remove(h.address);

                    return null;
                }
            }
        }

        return m.info;
    }

    string remove(EntityInfo i)
    {
        string addr;
        if(!this._shouldStop)
        {
            addr = i.ptr.id~"@"~i.ptr.domain; 
            synchronized(this._lock.writer)
            {            
                if(addr in this._local) {    
                    auto h = this._local[addr];
                    this.writeDebug("{REMOVE} entity("~h.info.ptr.type~"|"~addr~")", 2);
                    h.dispose();
                    this._local.remove(addr);
                }
            }
        }
        return addr;
    }

    Hull get(EntityInfo i)
    {
        if(!this._shouldStop)
            synchronized(this._lock.reader)
                return this._local[i.ptr.id~"@"~i.ptr.domain];
        
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
            foreach(i; this.getReceiver(s.type))
            {
                auto acceptable = i.ptr.domain.startsWith(s.domain);
                if(acceptable)
                {
                    this.deliver(s, i.ptr);
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
            foreach(i; this.getReceiver(s.type))
            {
                auto acceptable = i.ptr.domain.startsWith(s.domain);
                if(acceptable)
                {
                    delivered = this.deliver(s, i.ptr);
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
                this.writeDebug("{SEND} signal("~s.type~", "~s.id.toString~") TO entity("~ e.id~"@"~e.domain~")", 3);

            bool isLocal;
            synchronized(this._lock.reader)
                isLocal = e is null || e.id~"@"~e.domain in this._local;
            if(isLocal)
                return this.receive(this.config.isolateMem ? s.clone.as!Signal : s, e);
            else{return false;/* TODO search online when implementing apache thrift*/}
        }

        return false;
    }

    bool receive(Signal s, EntityPtr e)
    {
        if(!this._shouldStop)
        {
            auto stype = s.type;
            auto addr = e.id~"@"~e.domain;
            this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity("~addr~")", 3);

            Hull h;
            synchronized(this._lock.reader)
                if(addr in this._local)
                    h = this._local[addr];

            if(h !is null)
                return h.receive(s);
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
        EntityInfo[] ret;
        if(!this._shouldStop)
        {
            this.writeDebug("{SEARCH} entities FOR signal("~signal~")", 4);

            synchronized(this._lock.reader)
            {
                foreach(id; this._local.keys)
                {
                    auto h = this._local[id];
                    auto i = h.info;
                    foreach(s; i.signals)
                    {
                        if(s == signal)
                        {
                            ret ~= i;
                            this.writeDebug("\t!!! entity("~i.ptr.type~"|"~h.address~")", 4);
                            break;
                        }
                    }
                    this.writeDebug("\t>>> entity("~i.ptr.type~"|"~h.address~")", 4);
                }
            }
        }

        return ret;
    }
}