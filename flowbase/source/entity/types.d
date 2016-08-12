module flowbase.entity.types;
import flowbase.entity.interfaces;
import flowbase.entity.exceptions;
import flowbase.entity.signals;

import core.time;
import core.thread;
import core.sync.mutex;
import std.traits;
import std.algorithm;

import flowbase.type.interfaces;
import flowbase.type.types;
import flowbase.listener.interfaces;
import flowbase.task.interfaces;
import flowbase.task.types;
import flowbase.signal.interfaces;
import flowbase.signal.types;

/// specifies an available resource
class Resource : IResource
{
    private string _id;
    @property string id(){return this._id;}

    private uint _available = 0;
    @property uint available(){return this._available;}

    private uint _total;
    @property uint total(){return this._total;}

    this(string id, uint total)
    {
        this._id = id;
        this._total = total;
    }
}

/// specifies a resource requirement
class ResourceReq : IResourceReq
{
    private string _id;
    @property string id(){return this._id;}

    private uint _required;
    @property uint required(){return this._required;}

    this(string id, uint required)
    {
        this._id = id;
        this._required = required;
    }

    bool eval(IResource res)
    {
        return res.id == this.id && res.available > this.required;
    }
}

/// manages entities inside a process
class EntityManager : IEntityManager
{
    private Mutex _lock;
    private List!IEntity _entities;
    private bool _isRunning = false;

    this()
    {
        this._lock = new Mutex;
        this._entities = new List!IEntity();
    }

    void add(IEntity entity)
    {
        synchronized(this._lock)
        {
            this._entities.put(entity);

            if(this._isRunning)
            {
                // TODO deserialize if there is some state saved

                entity.start();
            }
        }
    }

    void run()
    {
        synchronized(this._lock)
        {
            this._isRunning = true;

            // TODO deserialize if there is some state saved

            foreach(e; this._entities)
                e.start();
        }
    }

    IEntityRef getRef(IEntity entity)
    {
        return new EntityRef(entity);
    }

    IEntityRef[] get(string domain)
    {
        IEntityRef[] entities;
        foreach(e; this._entities)
        {
            // TODO if(Domain!(domain).match(e.domain))
                entities ~= e.reference;
        }

        return entities;
    }

    void signal(IEntityRef entity, IFlowSignal signal)
    {
        foreach(e; this._entities)
            if(entity == e.reference)
            {
                e.listener.receive(signal);

                break;
            }
    }

    ~this()
    {
        synchronized(this._lock)
        {
            // TODO serialize and save state if there is a serializer

            foreach(e; this._entities)
                e.stop();
        }
    }
}

class EntityRef : IEntityRef
{
    private string _id;
    private string _domain;
    private IResource[] _resources;
    private string[] _acceptedSignals;

    @property string id(){return this._id;}
    @property string domain(){return this._domain;}
    @property IResource[] resources(){return this._resources;}
    @property string[] acceptedSignals(){return this._acceptedSignals;}

    this(IEntity entity)
    {
        this._id = entity.id;
        this._domain = entity.domain;
        this._resources = entity.resources;
        this._acceptedSignals = entity.acceptedSignals;
    }
}

abstract class Entity : IEntity
{
    private Mutex _lock;
    private List!ITasker _tasker;

    private IEntityManager _manager;
    @property IEntityManager manager(){return this._manager;}
    package @property void manager(IEntityManager value){this._manager = value;}

    private IListener _listener;
    @property IListener listener(){return this._listener;}
    
    @property IEntitySerializer serializer(){return null;}

    @property string id(){return fullyQualifiedName!this;}
    abstract @property string domain();
    @property IEntityRef reference(){return this.manager.getRef(this);}
    @property IResource[] resources(){return null;}    
    @property string[] acceptedSignals(){return this._listener.acceptedSignals;}

    abstract @property EntityScope availability();
    
    private EntityState _state = EntityState.Halted;
    @property EntityState state(){return this._state;}
    protected @property void state(EntityState value)
    {
        if(this._state != value)
        {
            auto old = this._state;
            this._state = value;

            this.stateChanged.emit(this, old, value);
        }
    }
    
    private SStateChanged _stateChanged = new SStateChanged();
    @property SStateChanged stateChanged(){return this._stateChanged;}

    this()
    {
        this._lock = new Mutex;
        this._tasker = new List!ITasker();
    }

    void start()
    {
        synchronized(this._lock)
            this.onStart();
    }

    void start(string json)
    {
        synchronized(this._lock)
        {
            if(this.serializer !is null)
                this.serializer.deserialize(json);
            else throw new StateRestoreError(this.id, json);

            this.onStart();
        }
    }

    void start(byte[] binary)
    {
        synchronized(this._lock)
        {
            if(this.serializer !is null)
                this.serializer.deserialize(binary);
            else throw new StateRestoreError(this.id, binary);

            this.onStart();
        }
    }

    abstract void onStart();

    void sleep()
    {
        synchronized(this._lock)
        {
            this.state = EntityState.Sleeping;

            while(!this.checkAllTaskerSleeping())
                Thread.sleep(50.msecs);
        }
    }

    private bool checkAllTaskerSleeping()
    {
        auto allSleeping = true;

        foreach(c; this._tasker)
            allSleeping = allSleeping && c.isSleeping;

        return allSleeping;
    }

    void onSleep(){}

    void wake()
    {
        synchronized(this._lock)
            this.state = EntityState.Running;
    }

    void onWake(){}

    void stop()
    {
        synchronized(this._lock)
        {
            this.state = EntityState.Halted;

            foreach(c; this._tasker)
                destroy(c);
        }
    }

    void onStop(){}

    protected void signal(IFlowSignal signal)
    {
        new SignalCaster(signal, this.manager);
    }

    void createTasker(ITask task)
    {
        this._tasker.put(new Tasker(this, task));
    }
}