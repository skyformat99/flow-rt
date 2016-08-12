module flowbase.signal.types;
import flowbase.signal.interfaces;
import flowbase.signal.meta;

import core.sync.mutex;
import core.time;
import core.thread;

import flowbase.type.interfaces;
import flowbase.type.types;
import flowbase.entity.interfaces;

class SignalCaster : Thread
{
    private IFlowSignal _signal;
    private IEntityManager _manager;

    this(IFlowSignal signal, IEntityManager manager)
    {
        this._signal = signal;
        this._manager = manager;

        super(&this.run);
    }

    private void run()
    {
        if(is(this._signal : IUnicastSignal))
            (cast(IUnicastSignal)this._signal).connect(this._manager);
        else if(is(this._signal : IBroadcastSignal))
            (cast(IBroadcastSignal)this._signal).broadcast(this._manager);
    }
}

class UnicastSignal : IUnicastSignal
{
    mixin TFlowSignal;

    private Mutex _lock;
    private IList!IEntityRef _waiting;
    private IList!IEntityRef _refused;

    private UnicastState _state = UnicastState.Pending;
    @property UnicastState state(){synchronized(this._lock) return this._state;}

    private IEntityRef _acceptedBy;
    @property IEntityRef acceptedBy(){synchronized(this._lock) return this._acceptedBy;}

    private IResourceReq[] _requirements;
    @property IResourceReq[] requirements(){return this._requirements;}

    this(string id, string targetDomain, string dataDomain, IResourceReq[] requirements)
    {
        this._lock = new Mutex;
        this._id = id;
        this._targetDomain = targetDomain;
        this._dataDdomain = dataDomain;
        this._requirements = requirements;
        this._waiting = new List!IEntityRef;
        this._refused = new List!IEntityRef;
    }

    void connect(IEntityManager manager)
    {
        synchronized(this._lock)
        {
            uint tries = 0;
            while(this.acceptedBy is null && tries < 5)
            {
                tries++;
                uint cnt = 0;
                foreach(e; manager.get(this.targetDomain))
                {
                    if(!this._refused.contains(e))
                    {
                        auto reqOk = true;
                        foreach(req; this.requirements)
                        {
                            foreach(res; e.resources)
                            {
                                if(res.id == req.id)
                                    reqOk = reqOk && req.eval(res);

                                if(!reqOk) break;
                            }

                            if(!reqOk) break;
                        }

                        if(reqOk)
                        {
                            manager.signal(e, this);
                            this._waiting.put(e);
                            cnt++;
                        }
                    }

                    if(cnt > 10) // need not to contact more than 10 at once
                        break;
                }

                while(this._waiting.length > 0)
                    Thread.sleep(50.msecs);

                if(this.acceptedBy is null && tries < 5)
                    Thread.sleep(1000.msecs);
            }

            this._state = (this.acceptedBy !is null) ? UnicastState.Success : UnicastState.Fail;
        }
    }

    bool accept(IEntityRef entity)
    {
        synchronized(this._lock)
        {
            if(this.acceptedBy is null)
            {
                this._acceptedBy = entity;
                this._waiting.clear();
                this._refused.clear();
                return true;
            }
            else return false; 
        }
    }

    void refuse(IEntityRef entity)
    {
        synchronized(this._lock)
        {
            this._waiting.remove(entity);
            this._refused.put(entity);
        }
    }
}

class BroadcastSignal : IBroadcastSignal
{
    mixin TFlowSignal;
    
    this(string id, string dataDomain)
    {
        this._id = id;
        this._targetDomain = targetDomain;
        this._dataDdomain = dataDomain;
    }
    
    void broadcast(IEntityManager manager)
    {            
        foreach(e; manager.get(this.targetDomain))
        {
            manager.signal(e, this);
        }
    }
}