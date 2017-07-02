module __flow.ticker;

import core.thread, core.sync.rwmutex;
import std.uuid, std.datetime;

import __flow.data, __flow.type, __flow.entity, __flow.signal;
import flow.base.dev, flow.base.data, flow.base.signals, flow.base.interfaces;

/// ticker executing chains of ticks
class Ticker : Thread
{
    private void delegate(Ticker) _exitHandler;
    private ulong _seq;

    private Entity _entity;
    @property EntityInfo entity() {return this._entity.info;}

    private TickMeta _coming;
    @property TickMeta coming() {return this._coming;}

    private TickMeta _actual;
    @property TickMeta actual() {return this._actual;}

    @property Data context() {return this._entity.context;}

    this(Entity e, Signal signal, TickInfo initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._entity = e;

        this.entity.debugMsg(DL.Debug, "enqueuing tick", initTick);
        this._coming = this.createTick(initTick);
        this.coming.trigger = signal.id;
        this.coming.signal = signal;

        super(&this.loop);
    }
    
    this(Entity e, TickMeta initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._entity = e;

        this.entity.debugMsg(DL.Debug, "enqueuing tick", initTick);
        this._coming = initTick;

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

    private TickMeta createTick(TickInfo i, Data d = null) {
        auto m = new TickMeta;
        m.info = i;     
        m.previous = this.actual;
        m.data = d;
        if(m.previous !is null) {
            m.trigger = m.previous.trigger;
            m.signal = m.previous.signal;
        }

        return m;
    }

    /// creates a new ticker initialized with given tick
    void fork(TickInfo i, Data d = null) {
            auto m = this.createTick(i, d);
            m.trigger = this.actual.info.id;
            m.signal = this.actual.signal;
            this.fork(m);
    }

    /// creates a new ticker initialized with given tick
    void fork(TickMeta m) {
        this.entity.debugMsg(DL.Debug, "forking tick", m);
        this._entity.tick(m);
    }

    /// enques next tick in the chain
    void next(TickInfo i, Data d = null) {
        this.entity.debugMsg(DL.Debug, "enqueuing tick", i);
        auto m = this.createTick(i, d);
        m.trigger = this.actual.info.id;
        m.signal = this.actual.signal;

        this._coming = m;
    }

    void repeat() {
        this._coming = this.actual;
    }
    
    ListeningMeta listen(string s, string t) {
        return this._entity.listen(s, t);
    }

    void shut(ListeningMeta l) {
        this._entity.shut(l);
    }

    private void loop() {
        this.entity.debugMsg(DL.Debug, "ticker starts");

        while(!this._entity.state == EntityState.Running) {
            this._actual = this.coming;
            this._coming = null;

            if(Tick.canCreate(this.actual.info.type)) {
                auto t = Tick.create(this.actual, this);
                
                if(this._entity.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null) {
                    auto td = new TraceTickData;
                    auto ts = new TraceBeginTick;
                    ts.type = ts.dataType;
                    ts.data = td;
                    ts.data.group = this.actual.info.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this.actual.info.id;
                    ts.data.trigger = this.actual.trigger;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entity = this.entity.ptr;
                    ts.data.tick = this.actual.info.type;
                    this._entity.send(ts);
                }

                synchronized(t.as!ISync !is null ? this._entity.lock.writer : this._entity.lock.reader) {
                    try {
                        this.entity.debugMsg(DL.Debug, "executing tick", t);
                        t.run();
                        this.entity.debugMsg(DL.Debug, "finished tick", t);
                    }
                    catch(Exception ex) {
                        this.entity.debugMsg(DL.Info, "tick failed", ex);
                        try {
                            this.entity.debugMsg(DL.Info, "handling tick error", t);
                            t.error(exc);
                            this.entity.debugMsg(DL.Info, "tick error handled", t);
                        }
                        catch(Exception ex2) {
                            this.entity.debugMsg(DL.Warning, "handling tick error failed", ex2);
                        }
                    }
                }
                
                if(this._entity.tracing &&
                    this._entity.as!IStealth is null &&
                    t.as!IStealth is null) {
                    auto td = new TraceTickData;
                    auto ts = new TraceEndTick;
                    ts.type = ts.dataType;
                    ts.data = td;
                    ts.data.group = this.actual.info.group;
                    ts.data.nature = "Tick";
                    ts.data.id = this.actual.info.id;
                    ts.data.trigger = this.actual.trigger;
                    ts.data.time = Clock.currTime.toUTC();
                    ts.data.entity = this.entity.ptr;
                    ts.data.tick = this.actual.info.type;
                    this._entity.send(ts);
                }
            }
            else break;
        }

        this._isStopped = true;
        if(this._exitHandler !is null) this._exitHandler(this);
        this.entity.debugMsg(DL.Debug, "ticker ends");
    }
}

mixin template TTick() {
    import __flow.type, __flow.ticker;
    static import flow.base.data;

    override @property string __fqn() {return fqn!(typeof(this));}

    static Tick create(flow.base.data.TickMeta m, Ticker t) {
        auto tick = new typeof(this)();
        tick.initialize(m, t);
        return tick;
    }

    shared static this() {
        Tick.register(fqn!(typeof(this)), &create);
    }

    this() {}
}

abstract class Tick : __IFqn {
	private shared static Tick function(TickMeta, Ticker)[string] _reg;

	static void register(string tickType, Tick function(TickMeta, Ticker) creator) {
		_reg[tickType] = creator;
	}

	static bool canCreate(string tickType) {
		return tickType in _reg ? true : false;
	}

	static Tick create(TickMeta m, Ticker t) {
		if(m.info.type in _reg) {
            auto tick = _reg[m.info.type](m, t);
			return tick;
        }
		else
			return null;
	}
    
	abstract @property string __fqn();

    private TickMeta _meta;
    private Ticker _ticker;

    @property EntityInfo entity() {return this._ticker.entity;}
    @property TickInfo info() {return this._meta.info;}
    @property UUID trigger() {return this._meta.trigger;}
    @property Signal signal() {return this._meta.signal;}
    @property TickInfo previous() {return this._meta.previous.info;}
    @property Data data() {return this._meta.data;}
    @property Data context() {return this._ticker.context;}

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
            s.as!Unicast.destination = this._meta.signal.source;

        return this.send(s);
    }

    /// sends a signal into the swarm
    bool send(Signal s) {
        auto success = false;

        s.id = randomUUID;
        if(s.group == UUID.init) // only set group if its not already set
            s.group = this._meta.info.group;
        s.source = this._ticker.entity.ptr;
        s.type = s.dataType;

        this.writeDebug("{SEND} signal("~s.type~")", 4);

        if(s.as!Multicast !is null
            && s.as!Multicast.domain == string.init)
            s.as!Multicast.domain = this.entity.ptr.domain;

        if(s.as!Unicast !is null)
            success = this._ticker._entity.send(s.as!Unicast);
        else if(s.as!Multicast !is null)
            success = this._ticker._entity.send(s.as!Multicast);
        else if(s.as!Anycast !is null)
            success = this._ticker._entity.send(s.as!Anycast);

        if(this._ticker._entity.tracing &&
            s.as!IStealth is null) {
            auto td = new TraceSignalData;
            auto ts = new TraceSend;
            ts.type = ts.dataType;
            ts.source = this._ticker.entity.ptr;
            ts.data = td;
            ts.data.group = s.group;
            ts.data.success = success;
            ts.data.nature = s.as!Unicast !is null ?
                "Unicast" : (
                    s.as!Multicast !is null ? "Multicast" :
                    "Anycast"
                );
            ts.data.trigger = this._meta.info.id;
            ts.data.id = s.id;
            ts.data.time = Clock.currTime.toUTC();
            ts.data.type = s.type;
            this._ticker._entity.send(ts);
        }

        return success;
    }

    void fork(string t, Data d = null) {
        auto i = new TickInfo;
        i.id = randomUUID;
        i.type = t;
        i.group = this.info.group;
        this._ticker.fork(i, d);
    }

    void next(string t, Data d = null) {
        auto i = new TickInfo;
        i.id = randomUUID;
        i.type = t;
        i.group = this.info.group;
        this._ticker.next(i, d);
    }

    void repeat() {this._ticker.repeat();}

    void writeDebug(string msg, uint level) {
        //debugMsg("tick("~this._ticker.entity.ptr.type~", "~this._ticker.entity.ptr.id~");"~msg, level);
    }
}