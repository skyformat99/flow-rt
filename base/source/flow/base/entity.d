module flow.base.entity;

import core.sync.mutex;
import std.uuid, std.array, std.datetime;
import std.algorithm.iteration, std.algorithm.searching;

import flow.base.tick, flow.base.type, flow.base.data;
import flow.dev, flow.interfaces, flow.signals, flow.data, flow.ticks;

/// listener meta informations
struct ListenerMeta
{
    string signal;
    Object function(IEntity, IFlowSignal) handle;
}

/// generates listener meta informations to use by an entity
mixin template TListen(string signal, Object function(IEntity, IFlowSignal) handle)
{
    import flow.base.entity;
    
    shared static this()
    {
        Listener ~= ListenerMeta(signal, handle);
    }
}

struct entityProps
{
    bool trace = true;
}

mixin template TEntity(T = void)
    if(is(T == void) || is(T : Object))
{
    import std.uuid;
    import flow.interfaces;
    import flow.base.entity, flow.base.type;

    static ListenerMeta[] Listener; 

    override @property string __fqn() {return fqn!(typeof(this));}

    static if(!is(T == void))
    {
        protected T _context;
        override @property T context() {return this._context;}
    }
    else
    {
        protected Object _context;
        override @property Object context() {return this._context;}
    }

    this()
    {this(randomUUID, "", EntityScope.Global, null, null, null);}

    this(Object context)
    {this(randomUUID, "", EntityScope.Global, null, context, null);}

    this(string domain, Object context)
    {this(randomUUID, domain, EntityScope.Global, null, context, null);}

    this(Object context, Data settings)
    {this(randomUUID, "", EntityScope.Global, null, context, settings);}

    this(string domain, Object context, Data settings)
    {this(randomUUID, domain, EntityScope.Global, null, context, settings);}

    this(string domain)
    {this(randomUUID, domain, EntityScope.Global, null, null, null);}
    
    this(UUID id, string domain, EntityScope availability)
    {this(id, domain, availability, null, null, null);}
    
    this(UUID id, string domain, EntityScope availability, ListenerMeta[] fListen)
    {this(id, domain, availability, fListen, null, null);}
    
    this(UUID id, string domain, EntityScope availability, Object context)
    {this(id, domain, availability, null, context, null);}

    this(UUID id, string domain, EntityScope availability, ListenerMeta[] fListen, Object context, Data settings)
    {
        static if(!is(T == void))
            this._context = context.as!T !is null ? context.as!T : new T;
        else
            this._context = context;

        this(id, domain, availability, fListen, settings);
    }

    this(UUID id, string domain, EntityScope availability, ListenerMeta[] fListen, Data settings)
    {
        super(id, domain, availability, fListen !is null ? Listener ~ fListen : Listener, settings);
    }
}

class Listener
{
    private Mutex _lock;
    private Object function(IEntity, IFlowSignal)[UUID] _handles;

    private string _signal;
    @property string signal() {return this._signal;}

    private IInvokingEntity _entity;
    @property IEntity entity() {return this._entity;}

    this(IInvokingEntity entity, string signal)
    {
        this._lock = new Mutex;
        this._entity = entity;
        this._signal = signal;
    }

    protected void writeDebug(string msg, uint level)
    {
        debugMsg("listener("~this._signal~", "~this.entity.id.toString~");"~msg, level);
    }

    UUID add(Object function(IEntity, IFlowSignal) handle)
    {
        synchronized(this._lock)
        {
            auto id = randomUUID;
            this._handles[id] = handle;
            return id;
        }
    }

    void remove(UUID id)
    {
        synchronized(this._lock)
        {
            if(id in this._handles)
                this._handles.remove(id);
        }
    }

    UUID[] list()
    {
        synchronized(this._lock)
            return this._handles.keys;
    }

    /// receive and handle a signal
    bool receive(IFlowSignal s)
    {
        if(s.source is null)
            this.writeDebug("{RECEIVE} signal("~s.type~", "~s.id.toString~") FROM entity(GOD)", 3);
        else
            this.writeDebug("{RECEIVE} signal("~s.type~", "~s.id.toString~") FROM entity("~s.source.type~", "~s.source.id.toString~")", 3);

        assert(s.type == this.signal);

        auto handled = false;
        foreach(handle; this._handles.values.dup)
        {
            Object invoking = null;
            synchronized(this._entity.lock)
                try {invoking = handle(this._entity, s);}
                catch(Exception exc) {debugMsg("{EXCEPTION}", 1);}
            if(invoking !is null)
            {
                this.writeDebug("{INVOKE}", 4);
                if(invoking.as!ITriggerAware !is null)
                    invoking.as!ITriggerAware.trigger = s;

                if(this._entity.process.tracing &&
                    s.as!IStealth is null)
                {
                    auto td = new TraceSignalData;
                    auto ts = new TraceReceive;
                    ts.id = s.id;
                    ts.type = ts.dataType;
                    ts.source = this._entity.info.reference;
                    ts.data = td;
                    if(s.source !is null)
                        ts.data.trigger = s.source.id;
                    ts.data.group = s.group;
                    ts.data.success = true;
                    ts.data.nature = s.as!IUnicast !is null ?
                        "Unicast" : (
                            s.as!IMulticast !is null ? "Multicast" :
                            "Anycast"
                        );
                    ts.data.id = s.id;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.type = s.type;
                    this._entity.process.send(ts);
                }

                this._entity.invoke(invoking);
                handled = true;
            }
        }
        
        if(!handled)
            this.writeDebug("{DENIED}", 4);

        return handled;
    }
}

    private Object handlePing(IEntity e, IFlowSignal s)
    {
        if(s.as!UPing !is null || (s.as!Ping !is null && s.source !is null && e.id != s.source.id))
            return new SendPong;

        return null;
    }

abstract class Entity : IInvokingEntity, ITickingEntity
{
    private Mutex _lock;
    private IFlowProcess _process;
    private flow.base.type.List!(Ticker) _ticker;
    protected bool _shouldStop;
    protected bool _isStopped = true;
    private Listener[string] _listeners;

    abstract @property string __fqn();
    @property Mutex lock(){return this._lock;}

    @property IFlowProcess process() {return this._process;}
    @property void process(IFlowProcess value) {this._process = value;}

    private EntityInfo _info;
    @property EntityInfo info() {return this._info;}
    @property UUID id() {return this.info.reference.id;}
    @property void id(UUID id) {throw new Exception("cannot set id of entity");}

    abstract @property Object context();
    
    @property bool running(){return !this._isStopped;}
    @property size_t count() {return this._ticker.length;}
            
    this(UUID id, string domain, EntityScope availability, ListenerMeta[] fListen, Data settings)
    {
        this._lock = new Mutex;
        this._ticker = new flow.base.type.List!(Ticker);

        auto listens = fListen;

        if(this.as!IQuiet is null)
        {
            auto pingListener = ListenerMeta(
                fqn!Ping,
                (e, s) => handlePing(e, s)
            );
            auto uPingListener = ListenerMeta(
                fqn!UPing,
                (e, s) => handlePing(e, s)
            );

            listens = [pingListener, uPingListener] ~ listens;
        }
        
        this._info = new EntityInfo;
        this._info.settings = settings;
        this._info.reference = new EntityRef;
        this._info.reference.id = id;
        this._info.reference.type = this.__fqn;
        this._info.domain = domain;
        this._info.availability = availability;

        if(listens != null)
            foreach(l; listens)
                this.beginListen(l.signal, l.handle);
    }
    
    ~this()
    {
        this.stop();
    }
    
    void writeDebug(string msg, uint level)
    {
        debugMsg("entity("~fqnOf(this)~", "~this.id.toString~");"~msg, level);
    }

    void create()
    {
        if(this._isStopped)
        {
            this.start();
            this._isStopped = false;
        }
    }
    
    void start(){}

    void dispose()
    {
        if(!this._shouldStop && !this._isStopped)
        {
            this._shouldStop = true;
            this._listeners.clear();

            auto ticker = this._ticker.array;
            foreach(t; ticker)
                if(t !is null)
                    t.stop();
            
            this.stop();
            this._isStopped = true;
        }
    }

    void stop(){}
    
    private void reloadListenerInfo()
    {
        this._info.signals.clear();
        if(this._listeners != null)
            this._info.signals.put(this._listeners.values.map!(l=>l.signal).array);
    }
    
    UUID beginListen(string s, Object function(IEntity, IFlowSignal) h)
    {
        synchronized(this._lock)
        {
            if(s !in this._listeners)
            {
                this.writeDebug("{LISTEN} signal("~s~")", 2);
                this._listeners[s] = new Listener(this, s);

                this.reloadListenerInfo();
            }

            return this._listeners[s].add(h);
        }
    }
    
    void endListen(UUID id)
    {
        synchronized(this._lock)
        {
            foreach(i, listener; this._listeners)
            {
                auto list = listener.list;

                if(list.array.any!(hid => hid == id))
                {
                    listener.remove(id);
                    if(listener.list.length < 1)
                    {
                        this._listeners.remove(i);
                        this.reloadListenerInfo();
                    }
                    break;
                }
            }
        }
    }
    
    bool receive(IFlowSignal s)
    {
        if(!this._isStopped)
        {
            this.writeDebug("{RECEIVE} signal("~s.type~", "~s.id.toString~")", 2);
            assert(s.type in this._listeners);
            
            return this._listeners[s.type].receive(s);
        } else return false;
    }

    void invoke(Object tick)
    {
        auto t = tick.as!ITick;
        if(t !is null)
            this.invokeTick(t);
    }
            
    void invokeTick(ITick tick)
    {
        auto ticker = new Ticker(this, tick.as!ITick,
            (t){synchronized(this._lock) this._ticker.remove(t);});

        synchronized(this._lock)
            this._ticker.put(ticker);

        ticker.start();
    }
}