module flow.base.tick;

import core.thread, core.sync.mutex;
import std.uuid, std.datetime;

import flow.base.data, flow.base.type;
import flow.dev, flow.interfaces, flow.data, flow.signals;

/// ticker executing chains of ticks
class Ticker : Thread, ITicker
{
    private void delegate(Ticker) _exitHandler;
    private bool _isStopped;
    private bool _shouldStop;
    private ITickingEntity _entity;
    private ITick _next;
    private ITick _last;
    private Mutex _lock;
    private ulong _seq;

    private UUID _id;
    @property UUID id() {return this._id;}
    @property void id(UUID id) {throw new Exception("cannot set id of ticker");}

    private IFlowSignal _trigger;
    @property IFlowSignal trigger() {return this._trigger;}
    @property void trigger(IFlowSignal value) {this._trigger = value;}

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    this(ITickingEntity entity, ITick initTick)
    {
        this._id = randomUUID();
        this._lock = new Mutex;
        this._entity = entity;

        this.next(initTick);

        super(&this.loop);
    }

    this(ITickingEntity entity, ITick initTick, void delegate(Ticker) exitHandler)
    {
        this._exitHandler = exitHandler;
        this(entity, initTick);
    }

    ~this()
    {
        this.stop();
    }
    
    void start()
    {
        super.start();
    }

    void stop()
    {
        if(!this._shouldStop)
        {
            this._shouldStop = true;

            while(this.isRunning)
                Thread.sleep(WAITINGTIME);

            this._isStopped = true;
        }
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("ticker("~fqnOf(this._entity)~", "~this._entity.id.toString~");"~msg, level);
    }

    /// suspends the chain
    void suspend()
    {
        if(!this._shouldStop) synchronized(this._lock)
        {
            this.writeDebug("{SUSPEND}", 3);
            this._isSuspended = true;
        }
    }

    /// resumes the chain
    void resume()
    {
        if(!this._shouldStop) synchronized(this._lock)
        {
            this.writeDebug("{RESUME}", 3);
            this._isSuspended = false;
        }
    }

    /// creates a new ticker initialized with given tick
    void fork(string tick, IData data = null)
    {
        auto t = Tick.create(tick, data);
        this.fork(t);
    }

    void fork(ITick t)
    {
        if(!this._shouldStop && t !is null) synchronized(this._lock)
        {
            this.writeDebug("{FORK} tick("~fqnOf(t)~")", 4);
            t.previous = this._last;
            this._entity.invokeTick(t);
        }
    }

    /// enques next tick in the chain
    void next(string tick, IData data = null)
    {
        auto t = Tick.create(tick, data);
        this.next(t);
    }

    private void next(ITick t)
    {
        if(!this._shouldStop) synchronized(this._lock)
        {
            if(t !is null)
            {
                this.writeDebug("{NEXT} tick("~fqnOf(t)~")", 4);

                if(this.trigger is null && t.trigger !is null)
                    this.trigger = t.trigger;
                else if(this.trigger !is null)
                    t.trigger = this.trigger;

                t.previous = this._last !is null ? this._last : t.previous;
                t.group = t.previous !is null ? t.previous.group : this.trigger.group;
                t.ticker = this;
                t.entity = this._entity;
            }
            this._next = t;
        }
    }

    void repeat()
    {
        this.next(this._last);
    }

    void repeatFork()
    {
        this.fork(this._last);
    }
    
    UUID beginListen(string s, Object function(IEntity, IFlowSignal) h)
    {
        return this._entity.beginListen(s, h);
    }

    void endListen(UUID id)
    {
        this._entity.endListen(id);
    }

    private void loop()
    {
        this.writeDebug("{START}", 3);

        while(!this._shouldStop)
        {
            ITick t;
            ITick lt;
            synchronized(this._lock)
            {
                t = this._next;
                this._last = this._next;
                this._next = null;
            }

            if(t !is null)
            {
                this.writeDebug("{RUN} tick("~fqnOf(t)~")", 4);
                
                if(this._entity.process.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null)
                {
                    auto td = new TraceTickData;
                    auto ts = new TraceBeginTick;
                    ts.type = ts.dataType;
                    ts.source = this._entity.info.reference;
                    ts.data = td;
                    ts.data.group = this._last.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this._last.id;
                    ts.data.trigger = this._seq == 0 ? this._trigger.id : t.previous.id;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this._entity.info.reference.type;
                    ts.data.entityId = this._entity.info.reference.id;
                    ts.data.ticker = this.id;
                    ts.data.seq = this._seq;
                    ts.data.tick = t.__fqn;
                    this._entity.process.send(ts);
                }

                if(t.as!ISync !is null)
                    synchronized(this._entity.lock)
                    {
                        try {t.run();}
                        catch(Exception exc)
                        {t.error(exc);}
                    }
                else
                {
                    try {t.run();}
                    catch(Exception exc)
                    {t.error(exc);}
                }
                
                if(this._entity.process.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null)
                {
                    auto td = new TraceTickData;
                    auto ts = new TraceEndTick;
                    ts.type = ts.dataType;
                    ts.source = this._entity.info.reference;
                    ts.data = td;
                    ts.data.group = this._last.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this._last.id;
                    ts.data.trigger = this._seq == 0 ? this._trigger.id : this._last.id;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this._entity.info.reference.type;
                    ts.data.entityId = this._entity.info.reference.id;
                    ts.data.ticker = this.id;
                    ts.data.seq = this._seq++;
                    ts.data.tick = t.__fqn;
                    this._entity.process.send(ts);
                }
            }
            else break;

            while(this._isSuspended)
                Thread.sleep(WAITINGTIME);
        }

        if(this._exitHandler !is null) this._exitHandler(this);
        this.writeDebug("{END}", 3);
    }
}

mixin template TTick()
{
    import flow.base.type;

    override @property string __fqn() {return fqn!(typeof(this));}

    static Tick create() {return new typeof(this);}
    shared static this()
    {
        Tick.register(fqn!(typeof(this)), &create);
    }
}

abstract class Tick : ITick
{
	private static Tick function()[string] _reg;

    private UUID _id;
    @property UUID id() {return this._id;}
    @property void id(UUID id) {throw new Exception("cannot set id of tick");}

    private UUID _group;
    @property UUID group() {return this._group;}
    @property void group(UUID group) {this._group = group;}

	static void register(string tickType, Tick function() creator)
	{
		_reg[tickType] = creator;
	}

	static bool knows(string tickType)
	{
		return tickType in _reg ? true : false;
	}

	static Tick create(string tickType, IData data = null)
	{
		if(tickType in _reg)
        {
            auto t = _reg[tickType]();
            t._data = data;
			return t;
        }
		else
			return null;
	}
    
	abstract @property string __fqn();

    private IEntity _entity;
    @property IEntity entity() {return this._entity;}
    @property void entity(IEntity value) {this._entity = value;}

    private ITicker _ticker;
    @property ITicker ticker() {return this._ticker;}
    @property void ticker(ITicker value) {this._ticker = value;}

    private ITick _previous;
    @property ITick previous() {return this._previous;}
    @property void previous(ITick value) {this._previous = value;}

    private IFlowSignal _trigger;
    @property IFlowSignal trigger() {return this._trigger;}
    @property void trigger(IFlowSignal value) {this._trigger = value;}

    private IData _data;
    @property IData data() {return this._data;}

    this(){this._id = randomUUID;}

    abstract void run();
    void error(Exception exc){}

    /// sends a unicast signal to a specific receiver
    bool send(IUnicast s, EntityRef e)
    {
        s.destination = e;
        return this.send(s);
    }

    /// sends a unicast signal to a specific receiver
    bool send(IUnicast s, EntityInfo e)
    {
        return this.send(s, e.reference);
    }

    /// sends a unicast signal to a specific receiver
    bool send(IUnicast s, IEntity e)
    {
        return this.send(s, e.info.reference);
    }

    /// answers a signal into the swarm
    bool answer(IFlowSignal s)
    {
        if(s.as!IUnicast !is null)
            s.as!IUnicast.destination = this.trigger.source;

        s.id = this.trigger.id;
        return this.send(s);
    }

    /// sends a signal into the swarm
    bool send(IFlowSignal s)
    {
        auto success = false;

        s.id = randomUUID;
        if(s.group == UUID.init)
            s.group = this.group;
        s.source = this.entity.info.reference;
        s.type = s.dataType;

        this.writeDebug("{SEND} signal("~s.type~")", 4);

        if(s.as!IMulticast !is null
            && s.as!IMulticast.domain is null)
            s.as!IMulticast.domain = this.entity.info.domain;

        if(s.as!IUnicast !is null)
            success = this.entity.process.send(s.as!IUnicast);
        else if(s.as!IMulticast !is null)
            success = this.entity.process.send(s.as!IMulticast);
        else if(s.as!IAnycast !is null)
            success = this.entity.process.send(s.as!IAnycast);

        if(this._entity.process.tracing &&
            s.as!IStealth is null)
        {
            auto td = new TraceSignalData;
            auto ts = new TraceSend;
            ts.type = ts.dataType;
            ts.source = this.entity.info.reference;
            ts.data = td;
            ts.data.group = s.group;
            ts.data.success = success;
            ts.data.nature = s.as!IUnicast !is null ?
                "Unicast" : (
                    s.as!IMulticast !is null ? "Multicast" :
                    "Anycast"
                );
            ts.data.trigger = this.id;
            ts.data.id = s.id;
            ts.data.time = Clock.currTime.toUTC();
            ts.data.type = s.type;
            this.entity.process.send(ts);
        }

        return success;
    }

    private void writeDebug(string msg, uint level)
    {
        debugMsg("tick("~fqnOf(this.entity)~", "~this.entity.id.toString~");"~msg, level);
    }
}