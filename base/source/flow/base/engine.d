module flow.base.engine;

import flow.base.util, flow.base.data;
import flow.data.base;

import core.thread, core.sync.rwmutex;
import std.uuid, std.string;

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

    void start() {
        this.state = SystemState.Ticking;
    }

    void stop(bool disposing = true) {
        this.disposing = disposing;
        this.state = SystemState.Frozen;
    }

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
                while(this.ticking)
                    Thread.sleep(5.msecs);

                if(this.disposing)
                    this.dispose();
                break;
            case SystemState.Destroyed:
                while(this.ticking)
                    Thread.sleep(5.msecs);
                break;
            default: break;
        }
    }

    void tick() {
        Tick t = this.coming.createTick(this);
        if(t !is null) {
            if(t.info.id == UUID.init)
                t.info.id = randomUUID;
    
            if(this.state == SystemState.Ticking) {
                this.ticking = true;
                try { this.runTick(t); }
                finally {this.ticking = false;}

                if(this.coming !is null)
                    this.entity.space.process.tasker.run(&this.tick);
                else {
                    this.msg(LL.FDebug, "nothing to do, ticker is ending");
                    this.stop();
                }
            } else {
                this.msg(LL.FDebug, "ticker is not ticking");
            }
        } else {
            this.msg(LL.Warning, "could not create tick -> ending");  
            if(this.state == SystemState.Ticking) this.stop();
        }
    }

    private void runTick(Tick t) {
        // check if entity is still running after getting the sync
        this.actual = t.meta;
        this.coming = null;

        try {
            this.msg(LL.FDebug, this.actual, "executing tick");
            t.run();
            this.msg(LL.FDebug, this.actual, "finished tick");
        }
        catch(Exception ex) {
            this.msg(LL.Warning, ex, "tick failed");
            try {
                this.msg(LL.Info, this.actual, "handling tick error");
                t.error(ex);
                this.msg(LL.Info, this.actual, "tick error handled");
            }
            catch(Exception ex2) {
                this.msg(LL.Warning, ex2, "handling tick error failed");
            }
        }
    }

    void next(TickInfo i, Data d) {
        this.coming = createTick(i, this.actual, d);
    }

    void fork(TickInfo i, Data d) {
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

class Tick {
    private Ticker ticker;
    private TickMeta meta;

    protected @property ReadWriteMutex sync() {return this.ticker.entity.sync;}
    protected @property EntityPtr entity() {return this.ticker.entity.meta.ptr;}
    protected @property Data context() {return this.ticker.entity.meta.context;}
    protected @property TickInfo info() {return this.meta.info;}
    protected @property Signal trigger() {return this.meta.trigger;}
    protected @property TickInfo previous() {return this.meta.previous;}
    protected @property Data data() {return this.meta.data;}

    public abstract void run();
    public void error(Exception ex) {}

    protected void next(string t, Data d = null) {
        this.ticker.next(this.createTick(t), d);        
    }

    protected void fork(string t, Data d = null) {
        this.ticker.fork(this.createTick(t), d);
    }

    protected EntityController get(EntityPtr e) {
        if(e.space != this.ticker.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be controlled");
        else return this.get(e.id);
    }

    private EntityController get(string e) {
        if(this.ticker.entity.meta.ptr.id == e)
            throw new TickException("entity cannot controll itself");
        else return this.ticker.entity.space.get(e);
    }

    protected EntityController spawn(EntityMeta e) {
        return this.ticker.entity.space.spawn(e);
    }

    protected void kill(EntityPtr e) {
        if(e.space != this.ticker.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be killed");
        this.kill(e.addr);
    }

    private void kill(string e) {
        if(this.ticker.entity.meta.ptr.addr == e)
            throw new TickException("entity cannot kill itself");
        else
            this.ticker.entity.space.kill(e);
    }

    protected bool send(Unicast s) {
        if(s is null)
            throw new TickException("cannot sand an empty unicast");

        if(s.dst is null || s.dst.id == string.init || s.dst.space == string.init)
            throw new TickException("unicast signal needs a valid dst");

        return this.ticker.entity.send(s);
    }

    protected bool send(Multicast s) {
        return this.ticker.entity.send(s);
    }
}

void msg(Tick t, LL level, string msg) {
    Log.msg(level, "tick@entity("~t.ticker.entity.meta.ptr.addr~"): "~msg);
}

void msg(Tick t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "tick@entity("~t.ticker.entity.meta.ptr.addr~"): "~msg);
}

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
    writeln("testing ticking (you should see exactly one \"tick failed\" warning in log)");

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

    // TODO
    // answer
    // spawn
    // kill
}

private enum SystemState {
    Frozen = 0,
    Ticking,
    Destroyed
}

private class Entity : StateMachine!SystemState {
    ReadWriteMutex sync;
    Space space;
    EntityMeta meta;

    private Ticker[UUID] ticker;

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

    void start(TickMeta t) {
        synchronized(this.sync.writer) {
            auto ticker = new Ticker(this, t);
            this.ticker[ticker.id] = ticker;
            ticker.start();
        }
    }

    void dispose(Ticker t) {
        synchronized(this.sync.writer)
            if(t.coming !is null)
                this.meta.ticks ~= t.coming;
            this.ticker.remove(t.id);
            t.destroy;
    }

    void freeze() {
        this.state = SystemState.Frozen;
    }

    void tick() {
        this.state = SystemState.Ticking;
    }

    bool receipt(Signal s) {
        auto ret = false;
        synchronized(this.sync.writer) {
            foreach(r; this.meta.receptors) {
                if(s.dataType == r.signal) {
                    auto ticker = new Ticker(this, r.tick.createTick(this, s));
                    this.ticker[ticker.id] = ticker;
                    ticker.start();
                    ret = true;
                }
            }
        }
        
        return ret;
    }

    bool send(Unicast s) {
        if(s.dst == this.meta.ptr)
            new EntityException("entity cannot send signals to itself, use fork");

        // also here we deep clone before passing its pointer
        s.src = this.meta.ptr.dup.as!EntityPtr;

        return this.space.send(s);
    }

    bool send(Multicast s) {
        // also here we deep clone before passing its pointer
        s.src = this.meta.ptr.dup.as!EntityPtr;

        return this.space.send(s);
    }

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

unittest {
    //auto p = new Process;
}