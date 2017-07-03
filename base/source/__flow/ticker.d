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
    private TickMeta _actual;
    private TickMeta _coming;

    public @property TickMeta actual() {return this._actual;}
    public @property TickMeta coming() {return this._coming;}

    this(Entity e, Signal signal, TickInfo initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._entity = e;

        this._entity.msg(DL.Debug, initTick, "enqueuing tick");
        this._coming = this.createTick(initTick);
        this.coming.trigger = signal.id;
        this.coming.signal = signal;

        super(&this.loop);
    }
    
    this(Entity e, TickMeta initTick, void delegate(Ticker) exitHandler) {
        this._exitHandler = exitHandler;
        
        this._entity = e;

        this._entity.msg(DL.Debug, initTick, "enqueuing tick");
        this._coming = initTick;

        super(&this.loop);
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
    public void fork(TickInfo i, Data d = null) {
        auto m = this.createTick(i, d);
        m.trigger = this.actual.info.id;
        m.signal = this.actual.signal;
        this.fork(m);
    }

    /// creates a new ticker initialized with given tick
    public void fork(TickMeta m) {
        this._entity.msg(DL.Debug, m, "forking tick");
        this._entity.tick(m);
    }

    /// enques next tick in the chain
    public void next(TickInfo i, Data d = null) {
        this._entity.msg(DL.Debug, i, "enqueuing tick");
        auto m = this.createTick(i, d);
        m.trigger = this.actual.info.id;
        m.signal = this.actual.signal;

        this._coming = m;
    }

    public void repeat() {
        this._coming = this.actual;
    }
    
    public ListeningMeta listenFor(string s, string t) {
        return this._entity.listenFor(s, t);
    }

    public void shut(ListeningMeta l) {
        this._entity.shut(l);
    }

    private void loop() {
        this._entity.msg(DL.Debug, "ticker starts");

        while(!this._entity.state == EntityState.Running) {
            this._actual = this.coming;
            this._coming = null;

            if(Tick.canCreate(this.actual.info.type)) {
                auto t = Tick.create(this.actual, this);
                
                if(this._entity.flow.config.tracing &&
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
                    ts.data.entity = this._entity.meta.info.ptr;
                    ts.data.tick = this.actual.info.type;
                    this._entity.send(ts);
                }

                synchronized(t.as!ISync !is null ? this._entity.sync.writer : this._entity.sync.reader) {
                    try {
                        this._entity.msg(DL.Debug, this.actual, "executing tick");
                        t.run();
                        this._entity.msg(DL.Debug, this.actual, "finished tick");
                    }
                    catch(Exception ex) {
                        this._entity.msg(DL.Info, ex, "tick failed");
                        try {
                            this._entity.msg(DL.Info, this.actual, "handling tick error");
                            t.error(ex);
                            this._entity.msg(DL.Info, this.actual, "tick error handled");
                        }
                        catch(Exception ex2) {
                            this._entity.msg(DL.Warning, ex2, "handling tick error failed");
                        }
                    }
                }
                
                if(this._entity.flow.config.tracing &&
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
                    ts.data.entity = this._entity.meta.info.ptr;
                    ts.data.tick = this.actual.info.type;
                    this._entity.send(ts);
                }
            }
            else break;
        }

        if(this._exitHandler !is null) this._exitHandler(this);
        this._entity.msg(DL.Debug, "ticker ends");
    }
}

mixin template TTick() {
    static import __flow.type, __flow.ticker;
    static import flow.base.data;

    override @property string __fqn() {return __flow.type.fqn!(typeof(this));}

    static __flow.ticker.Tick create(flow.base.data.TickMeta m, __flow.ticker.Ticker t) {
        auto tick = new typeof(this)(m, t);
        return tick;
    }

    shared static this() {
        __flow.ticker.Tick.register(__flow.type.fqn!(typeof(this)), &create);
    }

    this(flow.base.data.TickMeta m, __flow.ticker.Ticker t) {super(m, t);}
}

abstract class Tick : __IFqn {
	private shared static Tick function(TickMeta, Ticker)[string] _reg;

	public static void register(string tickType, Tick function(TickMeta, Ticker) creator) {
		_reg[tickType] = creator;
	}

	package static bool canCreate(string tickType) {
		return tickType in _reg ? true : false;
	}

	package static Tick create(TickMeta m, Ticker t) {
		if(m.info.type in _reg) {
            auto tick = _reg[m.info.type](m, t);
			return tick;
        }
		else
			return null;
	}
    
	public abstract @property string __fqn();

    private TickMeta _meta;
    private Ticker _ticker;

    protected @property EntityInfo entity() {return this._ticker._entity.meta.info;}
    protected @property TickInfo info() {return this._meta.info;}
    protected @property UUID trigger() {return this._meta.trigger;}
    protected @property Signal signal() {return this._meta.signal;}
    protected @property TickInfo previous() {return this._meta.previous.info;}
    protected @property Data context() {return this._ticker._entity.meta.context;}
    protected @property Data data() {return this._meta.data;}

    protected this(TickMeta m, Ticker t) {
        this._meta = m;
        this._ticker = t;
    }

    public abstract void run();
    public void error(Exception exc) {}

    /// sends a unicast signal to a specific receiver
    protected bool send(Unicast s, EntityPtr e) {
        s.destination = e;
        return this.send(s);
    }

    /// answers a signal into the swarm
    protected bool answer(Signal s) {
        if(s.as!Unicast !is null)
            s.as!Unicast.destination = this._meta.signal.source;

        return this.send(s);
    }

    /// sends a signal into the swarm
    protected bool send(Signal s) {
        auto success = false;

        s.id = randomUUID;
        if(s.group == UUID.init) // only set group if its not already set
            s.group = this._meta.info.group;
        s.source = this._ticker._entity.meta.info.ptr;
        s.type = s.dataType;

        if(s.as!Multicast !is null
            && s.as!Multicast.domain == string.init)
            s.as!Multicast.domain = this._ticker._entity.meta.info.ptr.domain;

        if(s.as!Unicast !is null)
            success = this._ticker._entity.send(s.as!Unicast);
        else if(s.as!Multicast !is null)
            success = this._ticker._entity.send(s.as!Multicast);
        else if(s.as!Anycast !is null)
            success = this._ticker._entity.send(s.as!Anycast);

        if(this._ticker._entity.flow.config.tracing &&
            s.as!IStealth is null) {
            auto td = new TraceSignalData;
            auto ts = new TraceSend;
            ts.type = ts.dataType;
            ts.source = this._ticker._entity.meta.info.ptr;
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

    protected void fork(string t, Data d = null) {
        auto i = new TickInfo;
        i.id = randomUUID;
        i.type = t;
        i.group = this.info.group;
        this._ticker.fork(i, d);
    }

    protected void next(string t, Data d = null) {
        auto i = new TickInfo;
        i.id = randomUUID;
        i.type = t;
        i.group = this.info.group;
        this._ticker.next(i, d);
    }

    protected void repeat() {this._ticker.repeat();}

    protected void msg(DL level, string msg) {
        this._ticker._entity.msg(level, msg);
    }
    
    protected void msg(DL level, Exception ex, string msg = string.init) {
        this._ticker._entity.msg(level, ex, msg);
    }

    protected void msg(DL level, Data d, string msg = string.init) {
        this._ticker._entity.msg(level, d, msg);
    }
}