module flow.flow.tick;

import core.thread, core.sync.mutex;
import std.uuid, std.datetime;

import flow.flow.data, flow.flow.type;
import flow.base.dev, flow.base.interfaces, flow.base.data, flow.base.signals;

/// ticker executing chains of ticks
class Ticker : Thread
{
    private void delegate(Ticker) _exitHandler;
    private bool _isStopped;
    private bool _shouldStop;
    private Mutex _lock;
    private ulong _seq;

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    private Entity _entity;
    @property EntityInfo entity() {return this._entity.meta.info;}
    @property Data context() {return this._entity.meta.context;}

    private TickMeta _next;
    @property TickMeta next() {return this._next;}

    private TickMeta _actual;
    @property TickMeta actual() {return this._actual;}

    this(Entity entity, TickMeta initTick)
    {
        this._lock = new Mutex;
        this._entity = entity;

        this.next(initTick);

        super(&this.loop);
    }

    this(Entity entity, TickMeta initTick, void delegate(Ticker) exitHandler)
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
        debugMsg("ticker("~fqnOf(this._entity)~", "~this._entity.meta.info.id.toString~");"~msg, level);
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
    void fork(TickMeta m)
    {
        if(!this._shouldStop && m !is null) synchronized(this._lock)
        {
            this.writeDebug("{FORK} tick("~m.info.type~")", 4);
            m.previous = this.actual;
            this._entity.invoke(m);
        }
    }

    /// enques next tick in the chain
    void next(TickMeta m)
    {
        if(!this._shouldStop) synchronized(this._lock)
        {
            m.previous = this.actual;
            if(m.previous !is null) {
                m.info.group = m.previous.info.group;
                m.trigger = m.previous.trigger;
            }
            
            if(t !is null)
            {
                this.writeDebug("{NEXT} tick("~m.info.type~")", 4);
                this._next = m;
            }
            else
            {
                // THROW no next tick exception
            }
        }
    }

    void repeat()
    {
        this.next(this.actual.meta);
    }

    void repeatFork()
    {
        this.fork(this.actual.meta);
    }
    
    UUID beginListen(string s, Object function(EntityInfo, Signal) h)
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
            TickMeta m;
            synchronized(this._lock)
            {
                m = this.next;
                this._actual = this.next;
                this._next = null;
            }

            auto t = Tick.create(m, this);
            if(t !is null)
            {
                this.writeDebug("{RUN} tick("~m.info.type~")", 4);
                
                if(this._entity.hull.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null)
                {
                    auto td = new TraceTickData;
                    auto ts = new TraceBeginTick;
                    ts.type = ts.dataType;
                    ts.source = this._entity.info.ptr;
                    ts.data = td;
                    ts.data.group = this._last.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this._last.id;
                    ts.data.trigger = this._seq == 0 ? this._trigger.id : t.previous.id;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this._entity.info.ptr.type;
                    ts.data.entityId = this._entity.info.ptr.id;
                    ts.data.ticker = this.id;
                    ts.data.seq = this._seq;
                    ts.data.tick = t.__fqn;
                    this._entity.hull.send(ts);
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
                
                if(this._entity.hull.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null)
                {
                    auto td = new TraceTickData;
                    auto ts = new TraceEndTick;
                    ts.type = ts.dataType;
                    ts.source = this._entity.info.ptr;
                    ts.data = td;
                    ts.data.group = this._last.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this._last.id;
                    ts.data.trigger = this._seq == 0 ? this._trigger.id : this._last.id;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this._entity.info.ptr.type;
                    ts.data.entityId = this._entity.info.ptr.id;
                    ts.data.ticker = this.id;
                    ts.data.seq = this._seq++;
                    ts.data.tick = t.__fqn;
                    this._entity.hull.send(ts);
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
    import flow.flow.type;

    override @property string __fqn() {return fqn!(typeof(this));}

    static Tick create(TickMeta m, Ticker t) {return new typeof(this)(m, t);}
    shared static this()
    {
        Tick.register(fqn!(typeof(this)), &create);
    }
}

abstract class Tick : __IFqn, IIdentified {
	private static Tick function(TickMeta, Ticker)[string] _reg;

	static void register(string tickType, Tick function(TickMeta, Ticker) creator) {
		_reg[tickType] = creator;
	}

	static bool canCreate(TickMeta m) {
		return m.type in _reg ? true : false;
	}

	static Tick create(TickMeta m, Ticker t) {
		if(m.type in _reg) {
            auto t = _reg[m.type](m, t);
			return t;
        }
		else
			return null;
	}
    
	abstract @property string __fqn();

    private TickMeta _meta;
    @property TickMeta meta() {return this._meta;}

    private ITicker _ticker;
    @property ITicker ticker() {return this._ticker;}
    @property void ticker(ITicker value) {this._ticker = value;}

    this(TickMeta m, Ticker t) {
        this._meta = m;
        this._ticker = t;
    }

    abstract void run();
    void error(Exception exc){}

    /// sends a unicast signal to a specific receiver
    bool send(Unicast s, EntityPtr e) {
        s.destination = e;
        return this.send(s);
    }

    /// sends a unicast signal to a specific receiver
    bool send(Unicast s, EntityInfo e) {
        return this.send(s, e.ptr);
    }

    /// sends a unicast signal to a specific receiver
    bool send(Unicast s, IEntity e) {
        return this.send(s, e.info.ptr);
    }

    /// answers a signal into the swarm
    bool answer(Signal s) {
        if(s.as!Unicast !is null)
            s.as!Unicast.destination = this.meta.trigger.source;

        s.id = this.meta.trigger.id;
        return this.send(s);
    }

    /// sends a signal into the swarm
    bool send(Signal s) {
        auto success = false;

        s.id = randomUUID;
        if(s.group == UUID.init)
            s.group = this.meta.group;
        s.source = this.ticker.entity.info.ptr;
        s.type = s.dataType;

        this.writeDebug("{SEND} signal("~s.type~")", 4);

        if(s.as!Multicast !is null
            && s.as!Multicast.domain is null)
            s.as!Multicast.domain = this.ticker.entity.domain;

        if(s.as!Unicast !is null)
            success = this.ticker._entity.hull.send(s.as!Unicast);
        else if(s.as!Multicast !is null)
            success = this.ticker._entity.hull.send(s.as!Multicast);
        else if(s.as!Anycast !is null)
            success = this.ticker._entity.hull.send(s.as!Anycast);

        if(this._entity.hull.tracing &&
            s.as!IStealth is null) {
            auto td = new TraceSignalData;
            auto ts = new TraceSend;
            ts.type = ts.dataType;
            ts.source = this.ticker.entity.ptr;
            ts.data = td;
            ts.data.group = s.group;
            ts.data.success = success;
            ts.data.nature = s.as!Unicast !is null ?
                "Unicast" : (
                    s.as!Multicast !is null ? "Multicast" :
                    "Anycast"
                );
            ts.data.trigger = this.meta.id;
            ts.data.id = s.id;
            ts.data.time = Clock.currTime.toUTC();
            ts.data.type = s.type;
            this.ticker._entity.hull.send(ts);
        }

        return success;
    }

    private void writeDebug(string msg, uint level) {
        debugMsg("tick("~this.ticker.entity.ptr.type~", "~this.ticker.entity.ptr.id.toString~");"~msg, level);
    }
}