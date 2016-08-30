module flow.base.process;

import core.thread, core.sync.mutex;
import std.uuid, std.range.interfaces, std.string;

import flow.base.type, flow.base.data;
import flow.dev, flow.interfaces, flow.data;

/// a flow process able to host the local swarm
class FlowProcess : IFlowProcess
{
    private bool _shouldStop;
    private bool _isStopped;
    private Mutex _lock;
    private IEntity[UUID] _local;
    private List!IOrgan _organs;

    private ProcessRef _reference;
    @property ProcessRef reference() {return this._reference;}

    private bool _tracing;
    @property bool tracing(){return this._tracing;}
    @property void tracing(bool value){this._tracing = value;}

    this()
    {
        this._organs = new List!IOrgan;
        this._lock = new Mutex;
        auto pf = new ProcessRef;
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

            foreach(o; this._organs)
                o.dispose();

            foreach(r, e; this._local)
                e.dispose();

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
            o.process = this;
            o.create();
            this._organs.put(o);
        }
    }

    UUID add(IEntity e)
    {
        if(!this._shouldStop)
        {
            auto worker = new Thread({
                synchronized(this._lock)
                {
                    this.writeDebug("{ADD} entity("~fqnOf(e)~", "~e.id.toString~")", 2);
                    this._local[e.id] = e;
                    e.process = this;
                    e.info.reference.process = this.reference;

                    try
                    {
                        e.create();
                    }
                    catch(Exception exc)
                    {
                        this.writeDebug("{ADD FAILED} entity("~fqnOf(e)~", "~e.id.toString~") ["~exc.msg~"]", 0);
                    }
                }
            });

            worker.start();
            worker.join();

            return e.id;
        } else return UUID.init;
    }

    void remove(IOrgan o)
    {
        if(!this._shouldStop)
        {
            this._organs.remove(o);
            o.dispose();
        }
    }

    void remove(UUID id)
    {
        if(!this._shouldStop)
        {
            auto worker = new Thread({
                synchronized(this._lock)
                {
                    auto e = this._local[id];
                    this.writeDebug("{REMOVE} entity("~fqnOf(e)~", "~e.id.toString~")", 2);
                    e.dispose();
                    this._local.remove(id);
                }
            });

            worker.start();
            worker.join();
        }
    }

    IEntity get(UUID id)
    {
        if(!this._shouldStop)
            synchronized(this._lock)
                return this._local[id];
        else return null;
    }

    private bool allFinished()
    {
        foreach(o; this._organs)
            if(!o.finished())
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

    private void giveIdAndTypeIfHasnt(IFlowSignal s)
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

    private bool deliverInternal(IFlowSignal s, EntityRef e)
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
                return this.receive(s.clone.as!IFlowSignal, e);
            else{return false;/* TODO search online when implementing apache thrift*/}
        }

        return false;
    }

    bool receive(IFlowSignal s, EntityRef e)
    {
        if(!this._shouldStop)
        {
            auto stype = s.type;
            if(e !is null)
                this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity("~ e.id.toString~")", 3);
            else
                this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity(GOD)", 3);

            IEntity entity;
            synchronized(this._lock)
                if(e !is null && e.id in this._local)
                    entity = this._local[e.id];

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
        // TODO when using thrift call InputRange!EntityInfo getReceiver(ProcessRef process, string type) of others and merge results
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
                    auto e = this._local[id].info;
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