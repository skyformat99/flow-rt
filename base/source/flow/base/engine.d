module flow.base.engine;

import flow.base.util, flow.base.data;
import flow.base.std;

import core.thread, core.sync.rwmutex;
import std.uuid, std.string;

private enum SystemState {
    Created = 0,
    Ticking,
    Frozen,
    Disposed
}

/// executes an entitycentric string of discretized causality 
private class Ticker : StateMachine!SystemState {
    bool detaching;
    
    UUID id;
    Entity entity;
    Tick actual;
    Tick coming;
    Exception error;

    private this(Entity b) {
        this.id = randomUUID;
        this.entity = b;

        super();
    }

    this(Entity b, Tick initial) {
        this(b);
        this.coming = initial;
        this.coming.ticker = this;
    }

    ~this() {
        if(this.state != SystemState.Disposed)
            this.dispose;
    }

    /// starts ticking
    void start(bool detaching = true) {
        this.detaching = detaching;
        this.state = SystemState.Ticking;
    }

    void join() {
        while(this.state == SystemState.Ticking)
            Thread.sleep(5.msecs);
    }

    /// stops ticking with or without causing dispose
    void stop() {
        this.state = SystemState.Frozen;
    }

    void dispose() {
        if(this.state == SystemState.Ticking)
            this.stop();

        this.state = SystemState.Disposed;
    }

    /// causes entity to dispose ticker
    void detach() {
        this.entity.detach(this);
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return o == SystemState.Created || o == SystemState.Frozen;
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Disposed:
                return o == SystemState.Created || o == SystemState.Frozen;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                this.tick();
                break;
            case SystemState.Frozen:
                // wait for executing tick to end
                while(this.actual !is null)
                    Thread.sleep(5.msecs);
                break;
            case SystemState.Disposed:
                // wait for executing tick to end
                while(this.actual !is null)
                    Thread.sleep(5.msecs);

                if(this.detaching)
                    this.detach();
                break;
            default: break;
        }
    }

    /// run coming tick if possible, is usually called by a tasker
    void tick() {
        try {
            if(this.coming !is null) {
                // if in ticking state try to run created tick or notify wha nothing happens
                if(this.state == SystemState.Ticking) {
                    // create a new tick of given type or notify failing and stop
                    if(this.coming !is null) {
                        this.entity.space.process.tasker.run(this.entity.meta.ptr.addr, this.coming.costs, &this.runTick);
                    } else {
                        this.msg(LL.Error, "could not create tick -> ending");
                        if(this.state != SystemState.Disposed) this.dispose;
                    }
                } else {
                    this.msg(LL.FDebug, "ticker is not ticking");
                }
            } else {
                this.msg(LL.FDebug, "nothing to do, ticker is ending");
                if(this.state != SystemState.Disposed) this.dispose;
            }
        } catch(Throwable thr) {
            this.msg(LL.Fatal, "unexcpected failure occured at 'engine.d: void Ticker::tick()'");
        }
    }

    /// run coming tick and handle exception if it occurs
    void runTick() {
        // check if entity is still running after getting the sync
        this.actual = this.coming;
        this.coming = null;

        try {
            // run tick
            this.msg(LL.FDebug, this.actual, "running tick");
            this.actual.run();
            this.msg(LL.FDebug, this.actual, "finished tick");
            
            this.actual = null;        
            this.tick();
        }
        catch(Exception ex) {
            // handle thrown exception and notify
            this.msg(LL.Warning, ex, "tick failed");
            try {
                this.msg(LL.Info, this.actual, "handling tick error");
                this.actual.error(ex);
                this.msg(LL.Info, this.actual, "tick error handled");
                
                this.actual = null;        
                this.tick();
            }
            catch(Exception ex2) {
                // if even handling exception failes notify that an error occured
                this.msg(LL.Error, ex2, "handling tick error failed");
                this.actual = null;
                if(this.state != SystemState.Disposed) this.dispose;
            }
        }
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

abstract class Tick : Data {
    mixin data;

    mixin field!(TickInfo, "info");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(Data, "data");

    private Ticker ticker;

    /// lock to use for synchronizing entity context access across parallel casual strings
    protected @property ReadWriteMutex sync() {return this.ticker.entity.sync;}

    /** context of hosting entity
    warning you have to sync as reader when accessing it reading
    and as writer when accessing it writing */
    protected @property Data context() {return this.ticker.entity.meta.context;}

    /// check if execution of tick is allowed
    public @property bool allowed() {return true;}

    /// predicted costs of tick (default=0)
    public @property size_t costs() {return 0;}

    /// algorithm implementation of tick
    public abstract void run();

    /// exception handling implementation of tick
    public void error(Exception ex) {}

    /// set next tick in causal string
    protected bool next(string tick, Data data = null) {
        auto t = this.ticker.entity.meta.createTick(tick, this.info.group);
        if(t !is null) {
            t.ticker = this.ticker;
            t.data = data;

            if(t.allowed) {
                this.ticker.coming = t;
                return true;
            } else return false;
        } else return false;
    }

    /** fork causal string by starting a new ticker
    given data will be deep cloned, since tick data has not to be synced */
    protected bool fork(string tick, Data data = null) {
        auto t = this.ticker.entity.meta.createTick(tick, this.info.group);
        if(t !is null) {
            t.ticker = this.ticker;
            t.data = data.clone;
            return this.ticker.entity.start(t);
        } else return false;
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
        if(s is null || createData(tick) is null)
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

        signal.group = this.info.group;

        return this.ticker.entity.send(signal);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Anycast signal) {
        signal.group = this.info.group;

        return this.ticker.entity.send(signal);
    }

    /// send a multicast signal to spaces matching space pattern
    protected bool send(Multicast signal, string space = string.init) {
        if(space != string.init) signal.space = space;

        if(signal.space == string.init)
            throw new TickException("multicast signal needs a space pattern");

        signal.group = this.info.group;

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

private Tick createTick(EntityMeta entity, string type, UUID group = UUID.init) {
    auto t = createData(type).as!Tick;
    if(t !is null) {
        t.info = new TickInfo;
        t.info.id = randomUUID;
        t.info.type = type;
        t.info.entity = entity.ptr.clone;
        t.info.group = group == UUID.init ? randomUUID : group;
    }

    return t;
}

class EntityMeta : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(EntityAccess, "access");
    mixin field!(Data, "context");
    mixin array!(Event, "events");
    mixin array!(Receptor, "receptors");

    mixin array!(Tick, "ticks");
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
        if(this.state != SystemState.Disposed)
            this.dispose;
    }

    /// starts a ticker
    bool start(Tick t) {
        auto ticker = new Ticker(this, t);
        if(this.state == SystemState.Ticking && t.allowed) {
            synchronized(this.sync.writer)
                this.ticker[ticker.id] = ticker;
            ticker.start();
            return true;
        }

        return false;
    }

    /// disposes a ticker
    void detach(Ticker t) {
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

    void dispose() {
        if(this.state == SystemState.Ticking)
            this.freeze();

        this.state = SystemState.Disposed;
    }

    /// registers a receptor if not registered
    void register(string s, string t) {
        synchronized(this.sync.writer) {
            foreach(r; this.meta.receptors)
                if(r.signal == s && r.tick == t)
                    return; // nothing to do

            auto r = new Receptor;
            r.signal = s;
            r.tick = t;
            this.meta.receptors ~= r; 
        }
    }

    /// deregisters a receptor if registerd
    void deregister(string s, string t) {
        import std.algorithm.mutation;

        synchronized(this.sync.writer) {
            foreach(i, r; this.meta.receptors) {
                if(r.signal == s && r.tick == t) {
                    this.meta.receptors.remove(i);
                    break;
                }
            }
        }
    }

    /// registers an event if not registered
    void register(EventType et, string t) {
        synchronized(this.sync.writer) {
            foreach(e; this.meta.events)
                if(e.type == et && e.tick == t)
                    return; // nothing to do

            auto e = new Event;
            e.type = et;
            e.tick = t;
            this.meta.events ~= e;
        }
    }

    /// deregisters an event if registerd
    void deregister(EventType et, string t) {
        import std.algorithm.mutation;

        synchronized(this.sync.writer) {
            foreach(i, e; this.meta.events) {
                if(e.type == et && e.tick == t) {
                    this.meta.events.remove(i);
                    break;
                }
            }
        }
    }

    /** receipts a signal only if entity is ticking,
    also an unicast signal can fork and tehrefore
    trigger multiple local strings of causality */
    bool receipt(Signal s) {
        auto ret = false;
        if(this.state == SystemState.Ticking) {
            synchronized(this.sync.writer) {
                // looping all registered receptors
                foreach(r; this.meta.receptors) {
                    if(s.dataType == r.signal) {
                        // creating given tick
                        auto t = this.meta.createTick(r.tick, s.group);
                        auto ticker = new Ticker(this, t);
                        if(t.allowed) {
                            synchronized(this.sync.writer)
                                this.ticker[ticker.id] = ticker;
                            ticker.start();
                            ret = true;
                        }
                    }
                }
            }
        }
        
        return ret;
    }

    /// send an unicast signal into own space
    bool send(Unicast s) {
        if(s.dst == this.meta.ptr)
            new EntityException("entity cannot send signals to itself, use fork");

        s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /// send an anycast signal into own space
    bool send(Anycast s) {
        s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /// send a multicast signal into own space
    bool send(Multicast s) {
        s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /** creates a snapshot of entity(deep clone)
    if entity is not in frozen state an exception is thrown */
    EntityMeta snap() {
        this.ensureState(SystemState.Frozen);
        // if someone snaps using this function, it is another entity. it will only get a deep clone.
        return this.meta.clone;
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return o == SystemState.Created || o == SystemState.Frozen;
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Disposed:
                return o == SystemState.Created || o == SystemState.Frozen;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        import std.algorithm.iteration;

        switch(n) {
            case SystemState.Created:
                synchronized(this.sync.writer) {
                    // running onCreated ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnCreated)) {
                        auto t = this.meta.createTick(e.tick);
                        if(t.allowed) {
                            auto ticker = new Ticker(this, t);
                            ticker.start(false);
                            ticker.join();
                            ticker.destroy();
                        }
                    }
                }
                break;
            case SystemState.Ticking:
                // here we need a writerlock since everyone could do that
                synchronized(this.sync.writer) {
                    // running onTicking ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnTicking)) {
                        auto t = this.meta.createTick(e.tick);
                        if(t.allowed) {
                            auto ticker = new Ticker(this, t);
                            ticker.start(false);
                            ticker.join();
                            ticker.destroy();
                        }
                    }

                    // creating and starting ticker for all frozen ticks
                    foreach(t; this.meta.ticks) {
                        auto ticker = new Ticker(this, t);
                        this.ticker[ticker.id] = ticker;
                        ticker.start();
                    }

                    // all frozen ticks are ticking -> empty store
                    this.meta.ticks = [];
                }
                break;
            case SystemState.Frozen: 
                synchronized(this.sync.writer) {
                    // stopping and destroying all ticker and freeze coming ticks
                    foreach(t; this.ticker.values.dup) {
                        t.detaching = false;
                        t.stop();
                        if(t.coming !is null)
                            this.meta.ticks ~= t.coming;
                        this.ticker.remove(t.id);
                        t.destroy();
                    }

                    // running onFrozen ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnFrozen)) {
                        auto t = this.meta.createTick(e.tick);
                        if(t.allowed) {
                            auto ticker = new Ticker(this, t);
                            ticker.start(false);
                            ticker.join();
                            ticker.destroy();
                        }
                    }
                }                    
                break;
            case SystemState.Disposed:
                synchronized(this.sync.writer) {
                    // running onDisposed ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnDisposed)) {
                        auto ticker = new Ticker(this, this.meta.createTick(e.tick));
                        ticker.start(false);
                        ticker.join();
                        ticker.destroy();
                    }
                }
                break;
            default: break;
        }
    }
}

string addr(EntityPtr e) {
    return e.id~"@"~e.space;
}

/// controlls an entity
class EntityController {
    private Entity _entity;

    /// deep clone of entity pointer of controlled entity
    @property EntityPtr entity() {return this._entity.meta.ptr.clone;}

    /// state of entity
    @property SystemState state() {return this._entity.state;}

    private this(Entity e) {
        this._entity = e;
    }

    /// makes entity freezing
    void freeze() {
        this._entity.freeze();
    }

    /// makes entity ticking
    void tick() {
        this._entity.tick();
    }

    /// snapshots entity (only working when entity is frozen)
    EntityMeta snap() {
        return this._entity.snap();
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

class SpaceMeta : Data {
    mixin data;

    mixin field!(string, "id");
    mixin array!(EntityMeta, "entities");
}

/// hosts a space construct
class Space : StateMachine!SystemState {
    private ReadWriteMutex sync;
    private SpaceMeta meta;
    private Process process;

    private Entity[string] entities;

    private this(Process p, SpaceMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.meta = m;
        this.process = p;

        super();

        this.init();
    }

    ~this() {
        if(this.state != SystemState.Disposed)
            this.state = SystemState.Disposed;
    }

    /// initializes space
    private void init() {
        foreach(em; this.meta.entities) {
            if(em.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~em.ptr.addr~"\" is already existing");
            else {
                Entity e = new Entity(this, em);
                this.entities[em.ptr.id] = e;
            }
        }
    }

    /// makes space and all of its content freezing
    void freeze() {
        this.state = SystemState.Frozen;
    }

    /// makes space and all of its content ticking
    void tick() {
        this.state = SystemState.Ticking;
    }

    void dispose() {
        if(this.state == SystemState.Ticking)
            this.freeze();

        this.state = SystemState.Disposed;
    }

    /// snapshots whole space (deep clone)
    SpaceMeta snap() {
        synchronized(this.sync.reader) {
            if(this.state == SystemState.Ticking) {
                this.state = SystemState.Frozen;
                scope(exit) this.state = SystemState.Ticking;
            }
            
            return this.meta.clone;
        }
    }

    /// gets a controller for an entity contained in space (null if not existing)
    EntityController get(string e) {
        synchronized(this.sync.reader)
            return (e in this.entities).as!bool ? new EntityController(this.entities[e]) : null;
    }

    /// spawns a new entity into space
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

    /// kills an existing entity in space
    void kill(string e) {
        synchronized(this.sync.writer) {
            if(e in this.entities) {
                this.entities[e].destroy;
                this.entities.remove(e);
            } else
                throw new SpaceException("entity with addr \""~e~"\" is not existing");
        }
    }
    
    /// routes an unicast signal to receipting entities if its in this space
    private bool route(Unicast s, bool intern = false) {
        // if its a perfect match assuming process only accepted a signal for itself
        if(this.state == SystemState.Ticking) {
            synchronized(this.sync.reader) {
                foreach(e; this.entities.values)
                    if((intern || e.meta.access == EntityAccess.Global) && e.meta.ptr == s.dst) {
                        return e.receipt(s);
                    }
            }
        }
        
        return false;
    }

   
    /// routes an anycast signal to one receipting entity
    private bool route(Anycast s) {
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        if(this.state == SystemState.Ticking) {
            synchronized(this.sync.reader) {
                foreach(e; this.entities.values)
                    if(e.receipt(s)) return true;
            }
        }

        return false;
    }
    
    /// routes a multicast signal to receipting entities if its addressed to space
    private bool route(Multicast s, bool intern = false) {
        auto r = false;
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        if(this.state == SystemState.Ticking && (s.space == this.meta.id || this.matches(s.space))) {
            synchronized(this.sync.reader) {
                foreach(e; this.entities.values)
                if(intern || e.meta.access == EntityAccess.Global)
                    r = e.receipt(s) || r;
            }
        }

        return r;
    }

    private bool send(Unicast s) {
        return this.route(s);
    }

    private bool send(Anycast s) {
        return this.route(s);
    }

    private bool send(Multicast s) {
        return this.route(s, true) || this.process.shift(s.clone);
    }

    override protected bool onStateChanging(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                return o == SystemState.Created || o == SystemState.Frozen;
            case SystemState.Frozen:
                return o == SystemState.Ticking;
            case SystemState.Disposed:
                return o == SystemState.Created || o == SystemState.Frozen;
            default: return false;
        }
    }

    override protected void onStateChanged(SystemState o, SystemState n) {
        switch(n) {
            case SystemState.Ticking:
                synchronized(this.sync.writer)
                    foreach(e; this.entities)
                        e.tick();
                break;
            case SystemState.Frozen:
                synchronized(this.sync.writer)
                    foreach(e; this.entities.values)
                        e.freeze();
                break;
            case SystemState.Disposed:
                synchronized(this.sync.writer)
                    foreach(e; this.entities.keys)
                        this.entities[e].destroy;
                break;
            default: break;
        }
    }
}

/** hosts one or more spaces and allows to controll them
whatever happens on this level, it has to happen in main thread or an exception occurs */
class Process {
    private ProcessConfig config;
    private Tasker tasker;
    private Space[string] spaces;

    this(ProcessConfig c = null) {
        import core.cpuid;
        // if no config given generate default one
        if(c is null)
            c = new ProcessConfig;

        // if worker amount lesser 1 use default (vcores - 1)
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

    /// shifting multicast signal from space to space also across nets
    private bool shift(Multicast s, bool intern = false) {
        auto r = false;
        if(s !is null) {
            foreach(spc; this.spaces.values)
                if(s.src.space != spc.meta.id)
                    r = spc.route(s) || r;
        }
        
        return r;
    }

    /// ensure it is executed in main thread or not at all
    private void ensureThread() {
        if(!thread_isMainThread)
            throw new ProcessError("process can be only controlled by main thread");
    }

    /// add a space
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

    /// get an existing space or null
    Space get(string s) {
        this.ensureThread();
        return (s in this.spaces).as!bool ? this.spaces[s] : null;
    }

    /// removes an existing space
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

    class TestSignal : Unicast {
        mixin data;
    }

    class TestTickContext : Data {
        mixin data;

        mixin field!(size_t, "cnt");
        mixin field!(string, "error");
        mixin field!(bool, "forked");
        mixin field!(TickInfo, "info");
        mixin field!(TestTickData, "data");
        mixin field!(TestSignal, "trigger");
        mixin field!(bool, "onCreated");
        mixin field!(bool, "onTicking");
        mixin field!(bool, "onFrozen");
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

    class TestOnCreatedTick : Tick {
        override void run() {
            auto c = this.context.as!TestTickContext;
            c.onCreated = true;
        }
    }

    class TestOnTickingTick : Tick {
        override void run() {
            auto c = this.context.as!TestTickContext;
            c.onTicking = true;
        }
    }

    class TestOnFrozenTick : Tick {
        override void run() {
            auto c = this.context.as!TestTickContext;
            c.onFrozen = true;
        }
    }

    class TriggeringTestContext : Data {
        mixin data;

        mixin field!(EntityPtr, "target");
    }

    class TriggeringTestTick : Tick {
        override void run() {
            auto c = this.context.as!TriggeringTestContext;
            this.send(new TestSignal, c.target);
        }
    }

    SpaceMeta createTestSpace() {
        auto s = new SpaceMeta;
        s.id = "s";
        auto te = createTestEntity();
        s.entities ~= te;
        auto tte = createTriggerTestEntity(te.ptr);
        s.entities ~= tte;

        return s;
    }

    EntityMeta createTestEntity() {
        auto e = new EntityMeta;
        e.ptr = new EntityPtr;
        e.ptr.id = "e";

        auto onc = new Event;
        onc.type = EventType.OnCreated;
        onc.tick = "flow.base.engine.TestOnCreatedTick";
        e.events ~= onc;
        auto ont = new Event;
        ont.type = EventType.OnTicking;
        ont.tick = "flow.base.engine.TestOnTickingTick";
        e.events ~= ont;
        auto onf = new Event;
        onf.type = EventType.OnFrozen;
        onf.tick = "flow.base.engine.TestOnFrozenTick";
        e.events ~= onf;

        auto r = new Receptor;
        r.signal = "flow.base.engine.TestSignal";
        r.tick = "flow.base.engine.TestTick";
        e.receptors ~= r;
        e.context = new TestTickContext;

        return e;
    }

    EntityMeta createTriggerTestEntity(EntityPtr te) {
        auto e = new EntityMeta;
        e.ptr = new EntityPtr;
        e.ptr.id = "te";
        auto tc = new TriggeringTestContext;
        tc.target = te;
        e.context = tc;
        e.ticks ~= e.createTick("flow.base.engine.TriggeringTestTick");

        return e;
    }
}

unittest {
    import std.stdio, std.conv;
    writeln("testing engine (you should see exactly one \"tick failed\" warning in log)");

    auto pc = new ProcessConfig;
    /* when there is one worker in taskpool, it has
    to be perfectly deterministic using limited complexity */
    pc.worker = 1;
    auto p = new Process(pc);
    scope(exit) p.destroy;
    auto s = p.add(createTestSpace());
    auto e = s.get("e");
    auto te = s.get("te");
    auto g = te._entity.meta.ticks[0].info.group;

    s.tick();

    // TODO
    // we have to wait for all systems to finish or we will get segfaults at the moment
    while(e._entity.ticker.keys.length > 0 || te._entity.ticker.keys.length > 0)
        Thread.sleep(5.msecs);

    s.freeze();
    
    auto sm = s.snap;
    assert(sm.entities.length == 2, "space snapshot does not contain correct amount of entities");
    assert(sm.entities[0].context.as!TestTickContext.onCreated, "onCreated entity event wasn't triggered");
    assert(sm.entities[0].context.as!TestTickContext.onTicking, "onTicking entity event wasn't triggered");
    assert(sm.entities[0].context.as!TestTickContext.onFrozen, "onFrozen entity event wasn't triggered");
    assert(sm.entities[0].context.as!TestTickContext.cnt == 6, "logic wasn't executed correct, got "~sm.entities[0].context.as!TestTickContext.cnt.to!string~" instead of 6");
    assert(sm.entities[0].context.as!TestTickContext.trigger !is null, "trigger was not passed correctly");
    assert(sm.entities[0].context.as!TestTickContext.trigger.group == g, "group was not passed correctly to signal");
    assert(sm.entities[0].context.as!TestTickContext.info.group == g, "group was not passed correctly to tick");
    assert(sm.entities[0].context.as!TestTickContext.data !is null, "data was not set correctly");
    assert(sm.entities[0].context.as!TestTickContext.error == "flow.base.engine.TestTickException", "error was not handled");
    assert(sm.entities[0].context.as!TestTickContext.forked, "didn't fork as expected");
}