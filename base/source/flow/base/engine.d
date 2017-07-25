module flow.base.engine;

import flow.base.util, flow.base.data, flow.base.tasker;
import flow.data.base;

import core.thread, core.sync.rwmutex;
import std.uuid, std.string;

package enum TickerState {
    Stopped = 0,
    Started,
    Destroyed
}

package class Ticker : StateMachine!TickerState {
    bool ticking;
    
    Entity entity;
    TickMeta actual;
    TickMeta coming;
    Exception error;

    private this(Entity b) {
        this.entity = b;
    }

    this(Entity b, TickMeta initial) {
        this(b);
        this.coming = initial;
    }

    ~this() {
        if(this.state != TickerState.Destroyed)
            this.state = TickerState.Destroyed;
    }

    void start() {
        this.state = TickerState.Started;
    }

    void stop() {
        this.state = TickerState.Stopped;
    }

    override protected bool onStateChanging(TickerState o, TickerState n) {
        switch(n) {
            case TickerState.Started:
                return o == TickerState.Stopped;
            case TickerState.Stopped:
                return o == TickerState.Started;
            case TickerState.Destroyed:
                return true;
            default: return false;
        }
    }

    override protected void onStateChanged(TickerState o, TickerState n) {
        switch(n) {
            case TickerState.Started:
                this.entity.space.process.tasker.run(&this.tick);
                break;
            case TickerState.Stopped:
            case TickerState.Destroyed:
                while(this.ticking)
                    Thread.sleep(5.msecs);
                break;
            default: break;
        }
    }

    void tick() {
        if(this.coming !is null) {
            Tick t = this.coming.createTick(this);
            if(t !is null) {
                if(t.ptr.id == UUID.init)
                    t.ptr.id = randomUUID;
        
                if(this.runTick(t) && this.coming !is null) {
                    this.entity.space.process.tasker.run(&this.tick);
                    return;
                } else {
                    if(this.state == TickerState.Started) this.stop();
                    this.msg(LL.FDebug, "nothing to do, ticker ends");
                }
            } else {
                if(this.state == TickerState.Started) this.stop();
                this.msg(LL.Error, "nothing to do, ticker ends");
            }
        } else {
            if(this.state == TickerState.Started) this.stop();
            this.msg(LL.FDebug, "nothing to do, ticker ends");
        }
    }

    private bool runTick(Tick t) {
        this.ticking = true;
        scope(exit) this.ticking = false;

        // check if entity is still running after getting the sync
        if(this.state == TickerState.Started) {
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

            return true;
        } else return false;
    }

    void next(TickPtr i, Data d) {
        this.coming = createTick(i, this.actual, d);
    }

    void fork(TickPtr i, Data d) {
        this.entity.start(createTick(i, this.actual, d));
    }
}

private void msg(Ticker t, LL level, string msg) {
    Log.msg(level, "ticker@entity("~t.entity.meta.ptr.address~"): "~msg);
}

private void msg(Ticker t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "ticker@entity("~t.entity.meta.ptr.address~"): "~msg);
}

private void msg(Ticker t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "ticker@entity("~t.entity.meta.ptr.address~"): "~msg);
}

class Tick {
    package Ticker ticker;
    package TickMeta meta;

    protected @property ReadWriteMutex sync() {return this.ticker.entity.sync;}
    protected @property EntityPtr entity() {return this.ticker.entity.meta.ptr;}
    protected @property Data context() {return this.ticker.entity.meta.context;}
    protected @property TickPtr ptr() {return this.meta.ptr;}
    protected @property Signal trigger() {return this.meta.trigger;}
    protected @property TickPtr previous() {return this.meta.previous;}
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
        return this.get(e.address);
    }

    protected EntityController get(string e) {
        if(this.ticker.entity.meta.ptr.address == e)
            throw new TickException("entity cannot controll itself");
        else
            return this.ticker.entity.space.get(e);
    }

    protected EntityController spawn(EntityMeta e) {
        return this.ticker.entity.space.add(e);
    }

    protected void kill(EntityPtr e) {
        this.kill(e.address);
    }

    protected void kill(string e) {
        if(this.ticker.entity.meta.ptr.address == e)
            throw new TickException("entity cannot kill itself");
        else
            this.ticker.entity.space.remove(e);
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
    Log.msg(level, "tick@entity("~t.ticker.entity.meta.ptr.address~"): "~msg);
}

void msg(Tick t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "tick@entity("~t.ticker.entity.meta.ptr.address~"): "~msg);
}

void msg(Tick t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "tick@entity("~t.ticker.entity.meta.ptr.address~"): "~msg);
}

private Tick createTick(TickMeta m, Ticker ticker) {
    auto t = Object.factory(ticker.coming.ptr.type).as!Tick;
    if(t !is null) {
        t.ticker = ticker;
        t.meta = m;
    }

    return t;
}

private TickPtr createTick(Tick tick, string t) {
    auto i = new TickPtr;
    i.id = randomUUID;
    i.type = t;
    i.group = tick.ptr.group;

    return i;
}

private TickMeta createTick(TickPtr t, TickMeta p, Data d = null) {
    auto m = new TickMeta;
    m.ptr = t;
    m.trigger = p.trigger;
    m.previous = p.ptr;
    m.data = d;

    return m;
}

version(unittest) {
    class TestTickException : Exception {this(){super(string.init);}}

    class TestSignal : Signal {
        mixin signal;
    }

    class TestTickContext : Data {
        mixin data;

        mixin field!(size_t, "cnt");
        mixin field!(bool, "error");
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
                "__flow.tick.TestTickData".createData().as!TestTickData;

            d.cnt++;

            if(d.cnt > 3)
                throw new TestTickException;
            
            synchronized(this.sync.writer)
                c.cnt += d.cnt;

            this.next("__flow.tick.TestTick", d);
        }

        override void error(Exception ex) {
            if(ex.as!TestTickException !is null) {
                auto c = this.context.as!TestTickContext;
                c.error = true;
            }
        }
    }
}

unittest {
    /*import flow.base.tasker;
    import std.stdio;
    writeln("testing ticking");

    auto tasker = new Tasker(1);
    tasker.start();
    scope(exit) tasker.stop();

    auto entity = new EntityMeta;
    entity.ptr = new EntityPtr;
    entity.ptr.id = "testentity";
    entity.ptr.space = "testspace";
    entity.ptr.process = "testprocess";
    entity.context = new TestTickContext;

    auto p = new Process;
    auto entity = new Entity(tasker, entity);

    auto s = new TestSignal;
    auto t1 = new TickPtr;
    t1.id = randomUUID;
    t1.type = "__flow.tick.TestTick";
    t1.group = randomUUID;
    auto ticker1 = new Ticker(entity, s, t1);
    ticker1.start();

    while(ticker1.state == TickerState.Started)
        Thread.sleep(5.msecs);

    assert(entity.context.as!TestTickContext.cnt == 6, "logic wasn't executed correct");
    assert(ticker1.actual.trigger.as!TestSignal !is null, "trigger was not passed correctly");
    assert(ticker1.actual.ptr.group == t1.group, "group was not passed correctly");
    assert(ticker1.actual.data.as!TestTickData !is null, "data was not set correctly");
    assert(ticker1.state == TickerState.Stopped, "ticker was left in wrong state");*/

    /*auto t2 = new TickPtr;
    t2.id = randomUUID;
    t2.type = "__flow.tick.TestTickNotExisting";
    t2.group = randomUUID;
    auto ticker2 = new Ticker(entity, s, t2);
    ticker2.start();

    while(ticker2.state == TickerState.Started)
        Thread.sleep(5.msecs);

    assert(ticker2.error !is null, "ticker should notify that it could not create tick");
    assert(ticker2.state == TickerState.Damaged, "ticker was left in wrong state");*/

    // TODO
    // fork
    // answer
    // send
    // spawn
    // kill (also killing itsetlf)
}

package enum SystemState {
    Frozen = 0,
    Ticking,
    Destroyed
}

package class Entity : StateMachine!SystemState {
    ReadWriteMutex sync;
    Space space;
    EntityMeta meta;

    private Ticker[] ticker;

    this(Space s, EntityMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        m.ptr.space = s.meta.ptr.id;
        m.ptr.process = s.meta.ptr.process;
        this.meta = m;
        this.space = s;
    }

    ~this() {
        if(this.state != SystemState.Destroyed)
            this.state = SystemState.Destroyed;
    }

    void start(TickMeta t) {
        synchronized(this.sync.writer) {
            auto ticker = new Ticker(this, t);
            this.ticker ~= ticker;
            ticker.start();
        }
    }

    void stop(Ticker t) {
        synchronized(this.sync.writer) {
            t.stop();
            if(t.coming !is null)
                this.meta.ticks ~= t.coming;
        }
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
                    this.ticker ~= ticker;
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
                        this.ticker ~= ticker;
                        ticker.start();
                    }
                break;
            case SystemState.Frozen:
                synchronized(this.sync.writer)
                    foreach(t; this.ticker) {
                        t.stop();
                        if(t.coming !is null)
                            this.meta.ticks ~= t.coming;
                    }
                break;
            case SystemState.Destroyed:
                synchronized(this.sync.writer)
                    foreach(t; this.ticker)
                        t.destroy;
                break;
            default: break;
        }
    }
}

package TickMeta createTick(string t, Entity e, Signal s) {
    auto m = new TickMeta;
    m.ptr = new TickPtr;
    m.ptr.entity = e.meta.ptr;
    m.ptr.type = t;
    m.ptr.group = s.group;
    m.trigger = s;

    return m;
}

string address(EntityPtr e) {
    return e.id~"@"~e.space~"@"~e.process;
}

class EntityController {
    package Entity entity;

    @property SystemState state() {return this.entity.state;}

    package this(Entity e) {
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

package bool matches(Space space, string pattern) {
    import std.regex, std.array;

    auto hit = false;
    auto s = matchAll(space.meta.ptr.id, regex("[A-Za-z]*")).array;
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

package class Space : StateMachine!SystemState {
    ReadWriteMutex sync;
    SpaceMeta meta;
    Process process;

    Entity[string] entities;

    this(Process p, SpaceMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        m.ptr.process = p.config.address;
        this.meta = m;
        this.process = p;
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
            if(e in this.entities)
                return new EntityController(this.entities[e]);
            else
                throw new SpaceException("entity with address \""~e~"\" is not existing");
    }

    EntityController add(EntityMeta m) {
        synchronized(this.sync.writer) {
            string addr = m.ptr.address;
            if(addr in this.entities)
                throw new SpaceException("entity with address \""~addr~"\" is already existing");
            else {
                this.meta.entities ~= m;
                Entity e = new Entity(this, m);
                this.entities[addr] = e;
                return new EntityController(e);
            }
        }
    }

    void remove(string e) {
        synchronized(this.sync.writer) {
            if(e in this.entities) {
                this.entities[e].destroy;
                this.entities.remove(e);
            } else
                throw new SpaceException("entity with address \""~e~"\" is not existing");
        }
    }
    
    bool route(Unicast s, bool intern = false) {
        // if its a perfect match assuming process only accepted a signal for itself
        if(s.dst.space == this.meta.ptr.id) {
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
        if(s.space == this.meta.ptr.id || this.matches(s.space)) {
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
                    foreach(e; this.entities)
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
    package ProcessConfig config;
    package Tasker tasker;
    package Space[string] spaces;

    this(ProcessConfig c = null, Tasker t = null) {
        this.config = c;
        this.tasker = t;
    }

    ~this() {
        foreach(s; this.spaces.keys)
            this.spaces[s].destroy;
    }

    /// shifting signal from junction to junction also across processes
    package bool shift(Unicast s, bool intern = false) {
        /* each time a pointer leaves a space
        it has to get dereferenced */
        if(intern) s.dst = s.dst.dup.as!EntityPtr;

        if((intern && s.dst.process == string.init) || s.dst.process == this.config.address)
            foreach(spc; this.spaces.values)
                if(spc.route(s, intern)) return true;
                
        return false;
        /* TODO return intern && net.port(s);*/
    }

    package bool shift(Multicast s, bool intern = false) {
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

    void add(SpaceMeta s) {
        this.ensureThread();
        
        if(s.ptr.id in this.spaces)
            throw new ProcessException("space with id \""~s.ptr.id~"\" is already existing");
        else
            this.spaces[s.ptr.id] = new Space(this, s);
    }

    bool exists(string s) {
        this.ensureThread();

        return (s in this.spaces).as!bool;
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