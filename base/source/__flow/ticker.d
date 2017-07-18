module __flow.ticker;

import core.thread, core.sync.rwmutex;
import std.uuid, std.datetime;

import __flow.data, __flow.type, __flow.entity, __flow.signal;
import flow.base.dev, flow.base.error, flow.base.data, flow.base.signals, flow.base.interfaces;

/// ticker executing chains of ticks
class Ticker
{
    private ulong _seq;

    private Entity entity;
    private TickMeta _actual;
    private TickMeta _coming;

    package @property TickMeta actual() {return this._actual;}
    package @property TickMeta coming() {return this._coming;}

    this(Entity e, Signal signal, TickInfo initTick) {        
        this.entity = e;

        this.entity.msg(DL.FDebug, initTick, "enqueuing tick");
        this._coming = this.createTick(initTick);
        this.coming.trigger = signal.id;
        this.coming.signal = signal;
    }
    
    this(Entity e, TickMeta initTick) {        
        this.entity = e;

        this.entity.msg(DL.FDebug, initTick, "enqueuing tick");
        this._coming = initTick;
    }

    public void start() {
        this.entity.flow.exec(&this.tick);
    }

    public void stop() {
        this.entity.stopTick(this);        
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
    package void fork(TickInfo i, Data d = null) {
        auto m = this.createTick(i, d);
        m.trigger = this.actual.info.id;
        m.signal = this.actual.signal;
        this.fork(m);
    }

    /// creates a new ticker initialized with given tick
    package void fork(TickMeta m) {
        this.entity.msg(DL.FDebug, m, "forking tick");
        this.entity.tick(m);
    }

    /// enques next tick in the chain
    package void next(TickInfo i, Data d = null) {
        this.entity.msg(DL.FDebug, i, "enqueuing tick");
        auto m = this.createTick(i, d);
        m.trigger = this.actual.info.id;
        m.signal = this.actual.signal;

        this._coming = m;
    }

    package void repeat() {
        this._coming = this.actual;
    }
    
    package ListeningMeta listenFor(string s, string t) {
        return this.entity.listenFor(s, t);
    }

    package void shut(ListeningMeta l) {
        this.entity.shut(l);
    }

    private void tick() {
        this.entity.msg(DL.FDebug, "ticker starts");

        try {
            if(this.entity.state == EntityState.Running) {
                this._actual = this.coming;
                this._coming = null;

                if(Tick.canCreate(this.actual.info.type)) {
                    auto t = Tick.create(this.actual, this);

                    if(t.info.id == UUID.init)
                        t.info.id = randomUUID;
                    
                    if(this.entity.flow.config.tracing &&
                        this.entity.as!IStealth is null &&
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
                        ts.data.entity = this.entity.meta.info.ptr;
                        ts.data.tick = this.actual.info.type;
                        this.entity.send(ts);
                    }

                    synchronized(t.sync ? this.entity.sync.writer : this.entity.sync.reader) {
                        try {
                            this.entity.msg(DL.FDebug, this.actual, "executing tick");
                            t.run();
                            this.entity.msg(DL.FDebug, this.actual, "finished tick");
                        }
                        catch(Exception ex) {
                            this.entity.msg(DL.Info, ex, "tick failed");
                            try {
                                this.entity.msg(DL.Info, this.actual, "handling tick error");
                                t.error(ex);
                                this.entity.msg(DL.Info, this.actual, "tick error handled");
                            }
                            catch(Exception ex2) {
                                this.entity.msg(DL.Warning, ex2, "handling tick error failed");
                            }
                        }
                    }
                    
                    if(this.entity.flow.config.tracing &&
                        this.entity.as!IStealth is null &&
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
                        ts.data.entity = this.entity.meta.info.ptr;
                        ts.data.tick = this.actual.info.type;
                        this.entity.send(ts);
                    }
                } else throw new TickException("unable to create", this.actual);

                if(this.coming !is null) {
                    this.entity.flow.exec(&this.tick);
                    return;
                } else {
                    this.stop();
                    this.entity.msg(DL.FDebug, "nothing to do, ticker ends");
                }
            }
            
            this.stop();
            this.entity.damage("entity not running, ticker ends", ex);
        } catch(Exception ex) {
            this.stop();
            this.entity.damage("ticker died", ex);
        }
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

    this(flow.base.data.TickMeta m, __flow.ticker.Ticker t) {super(m, t, false);}
}

mixin template TSync() {
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

    this(flow.base.data.TickMeta m, __flow.ticker.Ticker t) {super(m, t, true);}
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

    package bool sync;

    /*protected @property bool tracing() {return this._ticker.entity.flow.config.tracing;}*/
    protected @property EntityInfo entity() {return this._ticker.entity.meta.info;}
    protected @property TickInfo info() {return this._meta.info;}
    protected @property UUID trigger() {return this._meta.trigger;}
    protected @property Signal signal() {return this._meta.signal;}
    protected @property TickInfo previous() {return this._meta.previous.info;}
    protected @property Data context() {return this._ticker.entity.meta.context;}
    protected @property Data data() {return this._meta.data;}

    protected this(TickMeta m, Ticker t, bool sync) {
        this._meta = m;
        this._ticker = t;
        this.sync = sync;
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
        s.source = this._ticker.entity.meta.info.ptr;
        s.type = s.dataType;

        if(s.as!Multicast !is null
            && s.as!Multicast.domain == string.init)
            s.as!Multicast.domain = this._ticker.entity.meta.info.ptr.domain;

        if(s.as!Unicast !is null)
            success = this._ticker.entity.send(s.as!Unicast);
        else if(s.as!Multicast !is null)
            success = this._ticker.entity.send(s.as!Multicast);
        else if(s.as!Anycast !is null)
            success = this._ticker.entity.send(s.as!Anycast);

        if(this._ticker.entity.flow.config.tracing &&
            s.as!IStealth is null) {
            auto td = new TraceSignalData;
            auto ts = new TraceSend;
            ts.type = ts.dataType;
            ts.source = this._ticker.entity.meta.info.ptr;
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
            this._ticker.entity.send(ts);
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
        this._ticker.entity.msg(level, msg);
    }
    
    protected void msg(DL level, Exception ex, string msg = string.init) {
        this._ticker.entity.msg(level, ex, msg);
    }

    protected void msg(DL level, Data d, string msg = string.init) {
        this._ticker.entity.msg(level, d, msg);
    }
}