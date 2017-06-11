module flow.base.process;

import core.thread, core.sync.mutex;
import std.uuid, std.range.interfaces, std.string;

import flow.base.exception, flow.base.type, flow.base.data;
import flow.base.organ, flow.base.entity;
import flow.dev, flow.interfaces, flow.data;

/// a hull hosting an entity
class Hull(T) : IHull if(is(T == Entity) || is(T == Organ))
{
    private Flow _flow;
    private T _obj;

    this(Flow f, T o)
    {
        this._flow = f;
        this._obj = o;
        this._obj.hull = this;
    }

    @property T obj() { return this._obj; }

    @property FlowRef flow() { return this._flow.reference; }
    @property bool tracing() { return this._flow.tracing; }

    UUID add(IEntity e) { return this._flow.add(e); }
    void remove(UUID id) { return this._flow.remove(id); }
    IEntity get(UUID id) { return this._flow.get(id); }
    
    bool send(IUnicast s, EntityRef e)
    {
        if(this._flow._config.preventIdTheft)
        {
            static if(is(T == Entity))
                s.source = this.obj.info.reference;
            else
                s.source = null;
        }
        return this._flow.send(s, e);
    }
    bool send(IUnicast s, EntityInfo e) { return this.send(s, e.reference); }
    bool send(IUnicast s, IEntity e) { return this.send(s, e.info); }
    bool send(IUnicast s)
    {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    bool send(IMulticast s)
    {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    bool send(IAnycast s)
    {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }

    // wait for finish
    void wait(bool delegate() expr) { this._flow.wait(expr); }

    private void _preventIdTheft(ISignal s)
    {
        if(this._flow._config.preventIdTheft)
        {
            static if(is(T == Entity))
                s.source = this.obj.info.reference;
            else
                s.source = null;
        }
    }

    void dispose() { this._obj.dispose(); }
}

/// a flow process able to host the local swarm
class Flow : IFlow
{
    private FlowConfig _config;
    private bool _shouldStop;
    private bool _isStopped;
    private Mutex _lock;
    private Hull!Entity[UUID] _local;
    private Hull!Organ[UUID] _organs;

    private FlowRef _reference;
    @property FlowRef reference() { return this._reference; }

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
        auto pf = new FlowRef;
        pf.address = "";
        this._reference = pf;
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
            {
                foreach(o; this._organs)
                    o.dispose();

                foreach(r, e; this._local)
                    e.dispose();
            }

            this._isStopped = true;
        }
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("process();"~msg, level);
    }

    void add(IOrgan o)
    {
        if(!this._shouldStop)
        {
            auto obj = o.as!Organ;
            if(obj is null)
                throw new UnsupportedObjectTypeException();

            synchronized(this._lock)
            {
                auto m = new Hull!Organ(this, obj);
                m.obj.create();
                this._organs[obj.id] = m;
            }
        }
    }

    UUID add(IEntity e)
    {
        if(!this._shouldStop)
        {
            auto obj = e.as!Entity;
            if(obj is null)
                throw new UnsupportedObjectTypeException();
            
            synchronized(this._lock)
            {
                this.writeDebug("{ADD} entity("~fqnOf(e)~", "~e.id.toString~")", 2);
                auto m = new Hull!Entity(this, obj);
                this._local[obj.id] = m;
                obj.info.reference.process = this.reference;

                try
                {
                    e.create();
                }
                catch(Exception exc)
                {
                    this.writeDebug("{ADD FAILED} entity("~fqnOf(e)~", "~e.id.toString~") ["~exc.msg~"]", 0);
                }
            }

            return e.id;
        } else return UUID.init;
    }

    void remove(IOrgan o)
    {
        if(!this._shouldStop)
        {
            auto obj = o.as!Organ;
            if(obj is null)
                throw new UnsupportedObjectTypeException();
            
            synchronized(this._lock)
                this._organs.remove(obj.id);
            obj.dispose();
        }
    }

    void remove(UUID id)
    {
        if(!this._shouldStop)
        {
            synchronized(this._lock)
            {
                auto m = this._local[id];
                this.writeDebug("{REMOVE} entity("~fqnOf(m.obj)~", "~id.toString~")", 2);
                m.dispose();
                this._local.remove(id);
            }
        }
    }

    IEntity get(UUID id)
    {
        if(!this._shouldStop)
            synchronized(this._lock)
                return this._local[id].obj;
        else return null;
    }

    private bool allFinished()
    {
        synchronized(this._lock)
            foreach(id, m; this._organs)
                if(!m.obj.finished())
                    return false;
        
        return true;
    }

    void wait()
    {
        if(!this._shouldStop)
        {
            while(!allFinished)
                Thread.sleep(WAITINGTIME);
        }
    }

    void wait(bool delegate() expr)
    {
        if(!this._shouldStop)
        {
            while(!allFinished || !expr())
                Thread.sleep(WAITINGTIME);
        }
    }

    private void giveIdAndTypeIfHasnt(ISignal s)
    {
        if(s.id == UUID.init)
            s.id = randomUUID;

        if(s.type is null || s.type == "")
            s.type = s.dataType;
    }

    bool send(IUnicast s, EntityRef e)
    {
        s.destination = e;
        return this.send(s);
    }

    bool send(IUnicast s, EntityInfo e)
    {
        return this.send(s, e.reference);
    }

    bool send(IUnicast s, IEntity e)
    {
        return this.send(s, e.info.reference);
    }

    bool send(IUnicast s)
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
                    auto acceptable = r.reference.id == d.id;
                    if(acceptable)
                        return this.deliver(s, r.reference);
                }
            }
        }

        return false;
    }

    bool send(IMulticast s)
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
                    this.deliver(s, r.reference);
                    found = true;
                }
            }

            return found;
        }

        return false;
    }

    bool send(IAnycast s)
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
                    delivered = this.deliver(s, r.reference);
                    if(delivered) break;
                }
            }

            return delivered;
        }

        return false;
    }

    bool deliver(IUnicast s, EntityRef e)
    {
        return this.deliverInternal(s, e);
    }

    void deliver(IMulticast s, EntityRef e)
    {
        this.deliverInternal(s, e);
    }

    bool deliver(IAnycast s, EntityRef e)
    {
        return this.deliverInternal(s, e);
    }

    private bool deliverInternal(ISignal s, EntityRef e)
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
                return this.receive(s.clone.as!ISignal, e);
            else{return false;/* TODO search online when implementing apache thrift*/}
        }

        return false;
    }

    bool receive(ISignal s, EntityRef e)
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
        // TODO when using thrift call InputRange!EntityInfo getReceiver(FlowRef process, string type) of others and merge results
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
                            this.writeDebug("\t!!! entity("~e.reference.type~", "~e.reference.id.toString~")", 4);
                            break;
                        }
                    }
                    this.writeDebug("\t>>> entity("~e.reference.type~", "~e.reference.id.toString~")", 4);
                }
            }

            return found;
        }

        return null;
    }
}