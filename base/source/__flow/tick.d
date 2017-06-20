module __flow.tick;

import core.thread, core.sync.rwmutex;
import std.uuid, std.datetime;

import __flow.data, __flow.type, __flow.entity, __flow.signal;
import flow.base.dev, flow.base.interfaces, flow.base.data, flow.base.signals;

/// ticker executing chains of ticks
class Ticker : Thread
{
    private void delegate(Ticker) _exitHandler;
    private bool _isStopped;
    private bool _shouldStop;
    private ReadWriteMutex _lock;
    private ulong _seq;

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    private Entity _entity;
    @property EntityInfo entity() {return this._entity.meta.info;}

    private TickMeta _next;
    @property TickMeta next() {return this._next;}

    private TickMeta _actual;
    @property TickMeta actual() {return this._actual;}

    this(Entity entity, Signal signal, TickInfo initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._lock = new ReadWriteMutex;
        this._entity = entity;

        this.writeDebug("{NEXT} tick("~i.type~")", 4);
        this._next = this.createTick(i);
        this.next.trigger = signal.id;
        this.next.signal = signal;

        super(&this.loop);
    }
    
    this(Entity entity, TickMeta initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._lock = new ReadWriteMutex;
        this._entity = entity;

        this._next = initTick;

        super(&this.loop);
    }

    ~this() {
        this.stop();
    }
    
    void start() {
        super.start();
    }

    void stop() {
        if(!this._shouldStop) {
            this._shouldStop = true;

            while(!this._isStopped)
                Thread.sleep(WAITINGTIME);
        }
    }

    private void writeDebug(string msg, uint level) {
        debugMsg("ticker("~fqnOf(this._entity)~", "~this._entity.meta.info.id.toString~");"~msg, level);
    }

    /// suspends the chain
    void suspend() {
        if(!this._shouldStop) synchronized(this._lock.writer) {
            this.writeDebug("{SUSPEND}", 3);

            // mark loop for suspend
            this._shouldSuspend = true;

            // wait until loop suspended
            while(!this._isSuspended)
                Thread.sleep(WAITINGTIME);
        }
    }

    /// resumes the chain
    void resume() {
        if(!this._shouldStop) synchronized(this._lock.writer) {
            this.writeDebug("{RESUME}", 3);
            this._isSuspended = false;
        }
    }

    private TickMeta createTick(TickInfo i, Data c) {
        auto m = new TickMeta;
        m.info = i;     
        m.previous = this.actual;
        m.context = c;
        if(m.previous !is null) {
        }

        return m;
    }

    /// creates a new ticker initialized with given tick
    void fork(TickInfo i, Data c = null) {
        if(!this._shouldStop && i !is null) synchronized(this._lock.reader) {
            this.writeDebug("{FORK} tick("~i.type~")", 4);
            auto m = this.createTick(i, c);
            m.trigger = this.actual.id;
            m.signal = this.actual.signal;
            this._entity.invoke(m);
        }
    }

    /// enques next tick in the chain
    void next(TickInfo i, Data c = null) {
        if(!this._shouldStop) synchronized(this._lock.reader) {
            this.writeDebug("{NEXT} tick("~i.type~")", 4);
            auto m = this.createTick(i, c);
            m.trigger = this.actual.id;
            m.signal = this.actual.signal;

            this._next = m;
        }
    }

    void repeat() {
        this.next(this.actual);
    }

    void repeatFork() {
        this.fork(this.actual);
    }
    
    UUID beginListen(string s, TickInfo i) {
        return this._entity.beginListen(s, i);
    }

    void endListen(UUID id) {
        this._entity.endListen(id);
    }

    private void loop() {
        this.writeDebug("{START}", 3);

        while(!this._shouldStop) {
            TickMeta m;
            synchronized(this._lock.writer) {
                m = this.next;
                this._actual = this.next;
                this._next = null;
            }

            auto t = Tick.create(m, this);
            if(t !is null) {
                this.writeDebug("{RUN} tick("~m.info.type~")", 4);
                
                if(this._entity.hull.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null) {
                    auto td = new TraceTickData;
                    auto ts = new TraceBeginTick;
                    ts.type = ts.dataType;
                    ts.data = td;
                    ts.data.group = this.actual.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this.actual.id;
                    ts.data.trigger = this.actual.trigger;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this.entity.ptr.type;
                    ts.data.entityId = this.entity.ptr.id;
                    ts.data.ticker = this.id;
                    ts.data.tick = this.actual.info.type;
                    this._entity.hull.send(ts);
                }

                synchronized(t.as!ISync !is null ? this.entity.lock.writer : this.entity.lock.reader) {
                    try {t.run();}
                    catch(Exception exc)
                    {t.error(exc);}
                }
                
                if(this._entity.hull.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null) {
                    auto td = new TraceTickData;
                    auto ts = new TraceEndTick;
                    ts.type = ts.dataType;
                    ts.data = td;
                    ts.data.group = this.actual.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this.actual.id;
                    ts.data.trigger = this.actual.trigger;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entityType = this.entity.ptr.type;
                    ts.data.entityId = this.entity.ptr.id;
                    ts.data.ticker = this.id;
                    ts.data.tick = this.actual.info.type;
                    this._entity.hull.send(ts);
                }
            }
            else break;
        }

        this._isStopped = true;
        if(this._exitHandler !is null) this._exitHandler(this);
        this.writeDebug("{END}", 3);
    }
}

mixin template TTick() {
    import __flow.type;
    static import flow.base.data;

    override @property string __fqn() {return fqn!(typeof(this));}

    static Tick create(flow.base.data.TickMeta m, Ticker t) {
        auto tick = new typeof(this)(m, t);
        tick.initialize(m, t);
    }

    shared static this() {
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

    private Ticker _ticker;
    @property Ticker ticker() {return this._ticker;}
    @property void ticker(Ticker value) {this._ticker = value;}

    void initialize(TickMeta m, Ticker t) {
        this._meta = m;
        this._ticker = t;
    }

    abstract void run();
    void error(Exception exc) {}

    /// sends a unicast signal to a specific receiver
    bool send(Unicast s, EntityPtr e) {
        s.destination = e;
        return this.send(s);
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