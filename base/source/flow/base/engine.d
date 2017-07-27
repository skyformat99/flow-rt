module flow.base.engine;

import flow.base.util, flow.base.data;
import flow.data.base;

import core.thread, core.sync.rwmutex;
import std.uuid, std.string;

/// executes an entitycentric string of discretized causality 
private class Ticker : StateMachine!SystemState {
    bool ticking;
    bool disposing;
    
    UUID id;
    Entity entity;
    TickMeta actual;
    TickMeta coming;
    Exception error;

    private this(Entity b) {
        this.id = randomUUID;
        this.entity = b;

        super();
    }

    this(Entity b, TickMeta initial) {
        this(b);
        this.coming = initial;
    }

    ~this() {
        if(this.state != SystemState.Destroyed)
            this.state = SystemState.Destroyed;
    }

    /// starts ticking
    void start() {
        this.state = SystemState.Ticking;
    }

    /// stops ticking with or without causing dispose
    void stop(bool disposing = true) {
        this.disposing = disposing;
        this.state = SystemState.Frozen;
    }

    /// causes entity to dispose ticker
    void dispose() {
        this.entity.dispose(this);
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return o == SystemState.Frozen;
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Destroyed:
                return true;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                this.entity.space.process.tasker.run(&this.tick);
                break;
            case SystemState.Frozen:
                // wait for executing tick to end
                while(this.ticking)
                    Thread.sleep(5.msecs);

                // if stopped using disposing flag -> dispose
                if(this.disposing)
                    this.dispose();
                break;
            case SystemState.Destroyed:
                // wait for executing tick to end
                while(this.ticking)
                    Thread.sleep(5.msecs);
                break;
            default: break;
        }
    }

    /// run coming tick if possible, is usually called by a tasker
    void tick() {
        // create a new tick of given type or notify failing and stop
        Tick t = this.coming.createTick(this);
        if(t !is null) {
            t.info.id = randomUUID;
    
            // if in ticking state try to run created tick or notify wha nothing happens
            if(this.state == SystemState.Ticking) {
                this.ticking = true;
                try { this.runTick(t); }
                finally {this.ticking = false;}

                /* if tick enqueued another one, enqueue it into tasker or
                notify and stop if not done already by external instance */
                if(this.coming !is null)
                    this.entity.space.process.tasker.run(&this.tick);
                else {
                    this.msg(LL.FDebug, "nothing to do, ticker is ending");
                    if(this.state == SystemState.Ticking) this.stop();
                }
            } else {
                this.msg(LL.FDebug, "ticker is not ticking");
            }
        } else {
            this.msg(LL.Error, "could not create tick -> ending");  
            if(this.state == SystemState.Ticking) this.stop();
        }
    }

    /// run coming tick and handle exception if it occurs
    void runTick(Tick t) {
        // check if entity is still running after getting the sync
        this.actual = t.meta;
        this.coming = null;

        try {
            // run tick
            this.msg(LL.FDebug, this.actual, "running tick");
            t.run();
            this.msg(LL.FDebug, this.actual, "finished tick");
        }
        catch(Exception ex) {
            // handle thrown exception and notify
            this.msg(LL.Warning, ex, "tick failed");
            try {
                this.msg(LL.Info, this.actual, "handling tick error");
                t.error(ex);
                this.msg(LL.Info, this.actual, "tick error handled");
            }
            catch(Exception ex2) {
                // if even handling exception failes notify that an error occured
                this.msg(LL.Error, ex2, "handling tick error failed");
            }
        }
    }

    /// set next tick in causal string
    void next(TickInfo i, Data d) {
        this.coming = createTick(i, this.actual, d);
    }

    /// fork causal string by starting a new ticker
    void fork(TickInfo i, Data d) {
        /* since tick data needs not to be synchronized
        new causal branch has to have its own instance -> deep clone */
        if(d !is null) d = d.dup;

        this.entity.start(createTick(i, this.actual, d));
    }
}

private void msg(Ticker t, LL level, string msg) {
    Log.msg(level, "ticker@entity("~t.entity.meta.ptr.addr~"): "~msg);
}

private void msg(Ticker t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "ticker@entity("~t.entity.meta.ptr.addr~"): "~msg);
}

private void msg(Ticker t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "ticker@entity("~t.entity.meta.ptr.addr~"): "~msg);
}

abstract class Tick {
    private Ticker ticker;
    private TickMeta meta;

    /// lock to use for synchronizing entity context access across parallel casual strings
    protected @property ReadWriteMutex sync() {return this.ticker.entity.sync;}

    private EntityPtr _entity;
    /// pointer of hosting entity, just a deep clone we never pass references to others
    protected @property EntityPtr entity() {
        if(this._entity is null)
            this._entity = this.ticker.entity.meta.ptr.dup.as!EntityPtr;
        return this._entity;
    }

    /** context of hosting entity
    warning you have to sync as reader when accessing it reading
    and as writer when accessing it writing */
    protected @property Data context() {return this.ticker.entity.meta.context;}

    private TickInfo _info;
    /// info of current tick, again just a deep clone
    protected @property TickInfo info() {
        if(this._info is null)
            this._info = this.meta.info.dup.as!TickInfo;
        return this._info;
    }

    private Signal _trigger;
    /// signal wich triggered this part of causal string, again just a deep clone
    protected @property Signal trigger() {
        if(this._trigger is null)
            this._trigger = this.meta.trigger.dup.as!Signal;
        return this._trigger;
    }

    private TickInfo _previous;
    /// info of previous tick, again just a deep clone
    protected @property TickInfo previous() {
        if(this._previous is null)
            this._previous = this.meta.previous.dup.as!TickInfo;
        return this._previous;
    }

    /// data dedicated to this tick (only available to this tick, no need to sync)
    protected @property Data data() {return this.meta.data;}

    /// algorithm implementation of tick
    public abstract void run();

    /// exception handling implementation of tick
    public void error(Exception ex) {}

    /// set next tick in causal string
    protected void next(string tick, Data data = null) {
        this.ticker.next(this.createTick(tick), data);        
    }

    /** fork causal string by starting a new ticker
    given data will be deep cloned, since tick data has not to be synced */
    protected void fork(string tick, Data data = null) {
        this.ticker.fork(this.createTick(tick), data);
    }

    /// gets the entity controller of a given entity located in common space
    protected EntityController get(EntityPtr entity) {
        if(entity.space != this.ticker.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be controlled");
        else return this.get(entity.id);
    }

    private EntityController get(string e) {
        if(this.ticker.entity.meta.ptr.id == e)
            throw new TickException("entity cannot controll itself");
        else return this.ticker.entity.space.get(e);
    }

    /// spawns a new entity in common space
    protected EntityController spawn(EntityMeta entity) {
        return this.ticker.entity.space.spawn(entity);
    }

    /// killas a given entity in common space
    protected void kill(EntityPtr entity) {
        if(entity.space != this.ticker.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be killed");
        this.kill(entity.id);
    }

    private void kill(string e) {
        if(this.ticker.entity.meta.ptr.addr == e)
            throw new TickException("entity cannot kill itself");
        else
            this.ticker.entity.space.kill(e);
    }

    /// registers an receptor for signal which runs a tick
    protected void register(string signal, string tick) {
        auto s = createData(signal).as!Signal;
        auto t = createTick(tick, this.ticker.entity, s);
        if(s is null || t is null)
            throw new TickException("can only register receptors for valid signals and ticks");

        this.ticker.entity.register(signal, tick);
    }

    /// deregisters an receptor for signal running tick
    protected void deregister(string signal, string tick) {
        this.ticker.entity.deregister(signal, tick);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast signal, EntityPtr entity = null) {
        if(signal is null)
            throw new TickException("cannot sand an empty unicast");

        if(entity !is null) signal.dst = entity;

        if(signal.dst is null || signal.dst.id == string.init || signal.dst.space == string.init)
            throw new TickException("unicast signal needs a valid destination(dst)");

        return this.ticker.entity.send(signal);
    }

    /// send a multicast signal to spaces matching space pattern
    protected bool send(Multicast signal, string space = string.init) {
        if(space != string.init) signal.space = space;

        if(signal.space == string.init)
            throw new TickException("multicast signal needs a space pattern");

        return this.ticker.entity.send(signal);
    }
}

/// writes a log message
void msg(Tick t, LL level, string msg) {
    Log.msg(level, "tick@entity("~t.ticker.entity.meta.ptr.addr~"): "~msg);
}

/// writes a log message
void msg(Tick t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "tick@entity("~t.ticker.entity.meta.ptr.addr~"): "~msg);
}

/// writes a log message
void msg(Tick t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "tick@entity("~t.ticker.entity.meta.ptr.addr~"): "~msg);
}

private Tick createTick(TickMeta m, Ticker ticker) {
    auto t = Object.factory(ticker.coming.info.type).as!Tick;
    if(t !is null) {
        t.ticker = ticker;
        t.meta = m;
    }

    return t;
}

private TickInfo createTick(Tick tick, string t) {
    auto i = new TickInfo;
    i.id = randomUUID;
    i.type = t;
    i.group = tick.info.group;

    return i;
}

private TickMeta createTick(TickInfo t, TickMeta p, Data d = null) {
    auto m = new TickMeta;
    m.info = t;
    m.trigger = p.trigger;
    m.previous = p.info;
    m.data = d;

    return m;
}

private enum SystemState {
    Frozen = 0,
    Ticking,
    Destroyed
}

/// hosts an entity construct
private class Entity : StateMachine!SystemState {
    ReadWriteMutex sync;
    Space space;
    EntityMeta meta;

    Ticker[UUID] ticker;

    this(Space s, EntityMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        m.ptr.space = s.meta.id;
        this.meta = m;
        this.space = s;

        super();
    }

    ~this() {
        if(this.state != SystemState.Destroyed)
            this.state = SystemState.Destroyed;
    }

    /// starts a ticker
    void start(TickMeta t) {
        synchronized(this.sync.writer) {
            auto ticker = new Ticker(this, t);
            this.ticker[ticker.id] = ticker;
            ticker.start();
        }
    }

    /// disposes a ticker
    void dispose(Ticker t) {
        synchronized(this.sync.writer)
            if(t.coming !is null)
                this.meta.ticks ~= t.coming;
            this.ticker.remove(t.id);
            t.destroy;
    }

    /// meakes entity freeze
    void freeze() {
        this.state = SystemState.Frozen;
    }

    /// makes entity tick
    void tick() {
        this.state = SystemState.Ticking;
    }

    /// registers a receptor if not registered
    void register(string s, string t) {
        synchronized(this.sync.writer) {
            import std.algorithm.iteration;

            auto r = new Receptor;
            r.signal = s;
            r.tick = t;

            this.meta.receptors = this.meta.receptors.splitter(r).join();
            this.meta.receptors ~= r; 
        }
    }

    /// deregisters a receptor if registerd
    void deregister(string s, string t) {
        synchronized(this.sync.writer) {
            import std.algorithm.iteration;

            auto cr = new Receptor;
            cr.signal = s;
            cr.tick = t;
            
            this.meta.receptors = this.meta.receptors.splitter(cr).join();
        }
    }

    /** receipts a signal only if entity is ticking,
    also an unicast signal can fork and tehrefore
    trigger multiple local strings of causality */
    bool receipt(Signal s) {
        if(this.state == SystemState.Ticking) {
            auto ret = false;
            synchronized(this.sync.writer) {
                // looping all registered receptors
                foreach(r; this.meta.receptors) {
                    if(s.dataType == r.signal) {
                        // creating given tick
                        auto ticker = new Ticker(this, r.tick.createTick(this, s));
                        this.ticker[ticker.id] = ticker;
                        ticker.start();
                        ret = true;
                    }
                }
            }
            
            return ret;
        } else return false;
    }

    /// send an unicast signal into own space
    bool send(Unicast s) {
        if(s.dst == this.meta.ptr)
            new EntityException("entity cannot send signals to itself, use fork");

        // also here we deep clone before passing its pointer
        s.src = this.meta.ptr.dup.as!EntityPtr;

        return this.space.send(s);
    }

    /// send a multicast signal into own space
    bool send(Multicast s) {
        // also here we deep clone before passing its pointer
        s.src = this.meta.ptr.dup.as!EntityPtr;

        return this.space.send(s);
    }

    /** creates a snapshot of entity(deep clone)
    if entity is not in frozen state an exception is thrown */
    EntityMeta snap() {
        this.ensureState(SystemState.Frozen);
        // if someone snaps using this function, it is another entity. it will only get a deep clone.
        return this.meta.dup.as!EntityMeta;
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Ticking:
                return o == SystemState.Frozen;
            case SystemState.Destroyed:
                return true;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                // here we need a writerlock since everyone could do that
                synchronized(this.sync.writer)
                    // creating and starting ticker for all
                    foreach(t; this.meta.ticks) {
                        auto ticker = new Ticker(this, t);
                        this.ticker[ticker.id] = ticker;
                        ticker.start();
                    }
                break;
            case SystemState.Frozen: 
                synchronized(this.sync.writer) {
                    foreach(t; this.ticker.values.dup) {
                        t.stop(false);
                        if(t.coming !is null)
                            this.meta.ticks ~= t.coming;
                        this.ticker.remove(t.id);
                        t.destroy;
                    }
                }                    
                break;
            case SystemState.Destroyed:
                synchronized(this.sync.writer)
                    foreach(t; this.ticker.values) {
                        t.stop(false);
                        t.destroy;
                    }
                break;
            default: break;
        }
    }
}

private TickMeta createTick(string t, Entity e, Signal s) {
    auto m = new TickMeta;
    m.info = new TickInfo;
    m.info.entity = e.meta.ptr;
    m.info.type = t;
    m.info.group = s.group;
    m.trigger = s;

    return m;
}

string addr(EntityPtr e) {
    return e.id~"@"~e.space;
}

class EntityController {
    private Entity entity;

    @property SystemState state() {return this.entity.state;}

    private this(Entity e) {
        this.entity = e;
    }

    void freeze() {
        this.entity.freeze();
    }

    void tick() {
        this.entity.tick();
    }

    EntityMeta snap() {
        return this.entity.snap();
    }
}

private bool matches(Space space, string pattern) {
    import std.regex, std.array;

    auto hit = false;
    auto s = matchAll(space.meta.id, regex("[A-Za-z]*")).array;
    auto p = matchAll(pattern, regex("[A-Za-z\\*]*")).array;
    foreach(i, m; s) {
        if(p.length > i) {
            if(space.process.config.hark && m.hit == "*")
                hit = true;
            else if(m.hit != p[i].hit)
                break;
        } else break;
    }

    return hit;
}

private class Space : StateMachine!SystemState {
    ReadWriteMutex sync;
    SpaceMeta meta;
    Process process;

    Entity[string] entities;

    this(Process p, SpaceMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.meta = m;
        this.process = p;

        super();

        this.init();
    }

    void init() {
        foreach(em; this.meta.entities) {
            if(em.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~em.ptr.addr~"\" is already existing");
            else {
                Entity e = new Entity(this, em);
                this.entities[em.ptr.id] = e;
            }
        }
    }

    ~this() {
        if(this.state != SystemState.Destroyed)
            this.state = SystemState.Destroyed;
    }

    void freeze() {
        this.state = SystemState.Frozen;
    }

    void tick() {
        this.state = SystemState.Ticking;
    }

    SpaceMeta snap() {
        synchronized(this.sync.reader) {
            if(this.state == SystemState.Ticking) {
                this.state = SystemState.Frozen;
                scope(exit) this.state = SystemState.Ticking;
            }
            
            return this.meta;
        }
    }

    EntityController get(string e) {
        synchronized(this.sync.reader)
            return (e in this.entities).as!bool ? new EntityController(this.entities[e]) : null;
    }

    EntityController spawn(EntityMeta m) {
        synchronized(this.sync.writer) {
            if(m.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~m.ptr.addr~"\" is already existing");
            else {
                this.meta.entities ~= m;
                Entity e = new Entity(this, m);
                this.entities[m.ptr.id] = e;
                return new EntityController(e);
            }
        }
    }

    void kill(string e) {
        synchronized(this.sync.writer) {
            if(e in this.entities) {
                this.entities[e].destroy;
                this.entities.remove(e);
            } else
                throw new SpaceException("entity with addr \""~e~"\" is not existing");
        }
    }
    
    bool route(Unicast s, bool intern = false) {
        // if its a perfect match assuming process only accepted a signal for itself
        if(s.dst.space == this.meta.id) {
            synchronized(this.sync.reader) {
                foreach(e; this.entities.values)
                    if((intern || e.meta.ptr.access == Access.Global) && e.meta.ptr == s.dst) {
                        return e.receipt(s);
                    }
            }
        }
        
        return false;
    }
    
    bool route(Multicast s, bool intern = false) {
        auto r = false;
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        if(s.space == this.meta.id || this.matches(s.space)) {
            synchronized(this.sync.reader) {
                foreach(e; this.entities.values)
                    r = e.receipt(s) || r;
            }
        }

        return r;
    }

    bool send(T)(T s) if(is(T : Unicast) || is(T : Multicast)) {
        return this.route(s) || this.process.shift(s, true);
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Ticking:
                return o == SystemState.Frozen;
            case SystemState.Destroyed:
                return true;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                // here we need only a readerlock since only process can do that
                synchronized(this.sync.reader)
                    foreach(e; this.entities)
                        e.tick();
                break;
            case SystemState.Frozen:
                synchronized(this.sync.reader)
                    foreach(e; this.entities.values)
                        e.freeze();
                break;
            case SystemState.Destroyed:
                synchronized(this.sync.reader)
                    foreach(e; this.entities.keys)
                        this.entities[e].destroy;
                break;
            default: break;
        }
    }
}

class Process {
    private ProcessConfig config;
    private Tasker tasker;
    private Space[string] spaces;

    this(ProcessConfig c = null) {
        import core.cpuid;
        if(c is null)
            c = new ProcessConfig;

        if(c.worker < 1)
            c.worker = threadsPerCPU > 1 ? threadsPerCPU-1 : 1;

        this.config = c;
        this.tasker = new Tasker(c.worker);
        this.tasker.start();
    }

    ~this() {
        foreach(s; this.spaces.keys)
            this.spaces[s].destroy;

        this.tasker.stop();
        this.tasker.destroy;
    }

    /// shifting signal from space to space also across processes
    private bool shift(Unicast s, bool intern = false) {
        /* each time a pointer leaves a space
        it has to get dereferenced */
        if(intern) s.dst = s.dst.dup.as!EntityPtr;
        
        foreach(spc; this.spaces.values)
            if(spc.route(s, intern)) return true;
                
        return false;
        /* TODO return intern && net.port(s);*/
    }

    private bool shift(Multicast s, bool intern = false) {
        auto r = false;
        foreach(spc; this.spaces.values)
            r = spc.route(s, intern) || r;
        
        return r;
        /* TODO return (intern && net.port(s)) || r ); */
    }

    private void ensureThread() {
        if(!thread_isMainThread)
            throw new ProcessError("process can be only controlled by main thread");
    }

    Space add(SpaceMeta s) {
        this.ensureThread();
        
        if(s.id in this.spaces)
            throw new ProcessException("space with id \""~s.id~"\" is already existing");
        else {
            auto space = new Space(this, s);
            this.spaces[s.id] = space;
            return space;
        }
    }

    Space get(string s) {
        this.ensureThread();
        return (s in this.spaces).as!bool ? this.spaces[s] : null;
    }

    SpaceMeta snap(string s) {
        this.ensureThread();

        if(s in this.spaces)
            return this.spaces[s].snap();
        else
            throw new ProcessException("space with id \""~s~"\" is not existing");
    }

    void remove(string s) {
        this.ensureThread();

        if(s in this.spaces) {
            this.spaces[s].destroy;
            this.spaces.remove(s);
        } else
            throw new ProcessException("space with id \""~s~"\" is not existing");
    }
}

version(unittest) {
    class TestTickException : FlowException {mixin exception;}

    class TestSignal : Signal {
        mixin signal;
    }

    class TestTickContext : Data {
        mixin data;

        mixin field!(size_t, "cnt");
        mixin field!(string, "error");
        mixin field!(bool, "forked");
        mixin field!(TickInfo, "info");
        mixin field!(TestTickData, "data");
        mixin field!(TestSignal, "trigger");
    }

    class TestTickData : Data {
        mixin data;

        mixin field!(size_t, "cnt");
    }
    
    class TestTick : Tick {
        import flow.base.util;

        override void run() {
            auto c = this.context.as!TestTickContext;
            auto d = this.data.as!TestTickData !is null ?
                this.data.as!TestTickData :
                "flow.base.engine.TestTickData".createData().as!TestTickData;
            auto t = this.trigger.as!TestSignal;

            c.info = this.info;
            c.data = d;
            c.trigger = t;

            d.cnt++;

            if(d.cnt == 4) {
                this.fork(this.info.type, data);
                throw new TestTickException;
            } else if(d.cnt > 4) {
                c.forked = true;
            } else {            
                /* we do not really need to sync that beacause D
                syncs integrals automatically but we need an example */
                synchronized(this.sync.writer)
                    c.cnt += d.cnt;

                this.next("flow.base.engine.TestTick", d);
            }
        }

        override void error(Exception ex) {
            if(ex.as!TestTickException !is null) {
                auto c = this.context.as!TestTickContext;
                synchronized(this.sync.writer)
                    c.error = ex.as!FlowException.type;
            }
        }
    }

    SpaceMeta createTestSpace() {
        auto s = new SpaceMeta;
        s.id = "s";
        s.entities ~= createTestEntity();

        return s;
    }

    EntityMeta createTestEntity() {
        auto e = new EntityMeta;
        e.ptr = new EntityPtr;
        e.ptr.id = "e";
        e.context = new TestTickContext;
        e.ticks ~= createTestTick();

        return e;
    }

    TickMeta createTestTick() {
        auto t = new TickMeta;
        t.info = new TickInfo;
        t.info.id = randomUUID;
        t.info.type = "flow.base.engine.TestTick";
        t.info.group = randomUUID;
        t.trigger = new TestSignal;

        return t;
    }
}

unittest {
    import std.stdio;
    writeln("testing engine (you should see exactly one \"tick failed\" warning in log)");

    auto p = new Process;
    scope(exit) p.destroy;
    auto s = p.add(createTestSpace());
    auto e = s.get("e");
    auto g = e.entity.meta.ticks[0].info.group;

    s.tick();

    while(e.entity.ticker.keys.length > 0)
        Thread.sleep(5.msecs);

    s.freeze();
    
    auto em = e.snap;
    assert(em.context.as!TestTickContext.cnt == 6, "logic wasn't executed correct");
    assert(em.context.as!TestTickContext.trigger !is null, "trigger was not passed correctly");
    assert(em.context.as!TestTickContext.info.group == g, "group was not passed correctly");
    assert(em.context.as!TestTickContext.data !is null, "data was not set correctly");
    assert(em.context.as!TestTickContext.error == "flow.base.engine.TestTickException", "error was not handled");
    assert(em.context.as!TestTickContext.forked, "didn't fork as expected");
}