module flow.core.engine;

private import core.thread;
private import flow.core.data;
private import flow.util;
private import std.uuid;

private enum SystemState {
    Created = 0,
    Ticking,
    Frozen,
    Disposed
}

package enum ProcessorState {
    Stopped = 0,
    Started
}

private enum JobStatus : ubyte
{
    NotStarted,
    InProgress,
    Done
}

private struct Job {
    this(Tick t) {
        tick = t;
    }

    Job* prev;
    Job* next;

    Throwable exception;
    ubyte taskStatus = JobStatus.NotStarted;

    @property bool done() {
        import flow.util : atomicReadUbyte;
        if (atomicReadUbyte(taskStatus) == JobStatus.Done)
        {
            if (exception)
            {
                throw exception;
            }

            return true;
        }

        return false;
    }

    Tick tick;
}

private final class Pipe : Thread
{
    this(void delegate() dg)
    {
        super(dg);
    }

    Processor processor;
}

package final class Processor : StateMachine!ProcessorState {
    private import core.sync.condition : Condition;
    private import core.sync.rwmutex : ReadWriteMutex;
    private import core.sync.mutex : Mutex;

    private Pipe[] pipes;

    private Job* head;
    private Job* tail;
    private PoolState status = PoolState.running;
    private long nextTime;
    private Condition workerCondition;
    private Condition waiterCondition;
    private Mutex queueMutex;
    private Mutex waiterMutex; // For waiterCondition

    /// The instanceStartIndex of the next instance that will be created.
    __gshared static size_t nextInstanceIndex = 1;

    /// The index of the current thread.
    private static size_t threadIndex;

    /// The index of the first thread in this instance.
    immutable size_t instanceStartIndex;
    
    /// The index that the next thread to be initialized in this pool will have.
    private size_t nextThreadIndex;

    private enum PoolState : ubyte {
        running,
        finishing,
        stopNow
    }

    this(size_t nWorkers = 1) {

        synchronized(typeid(Processor))
        {
            instanceStartIndex = nextInstanceIndex;

            // The first worker thread to be initialized will have this index,
            // and will increment it.  The second worker to be initialized will
            // have this index plus 1.
            nextThreadIndex = instanceStartIndex;
            nextInstanceIndex += nWorkers;
        }

        this.queueMutex = new Mutex(this);
        this.waiterMutex = new Mutex();
        workerCondition = new Condition(queueMutex);
        waiterCondition = new Condition(waiterMutex);
        
        this.pipes = new Pipe[nWorkers];
    }

    override protected bool onStateChanging(ProcessorState o, ProcessorState n) {
        switch(n) {
            case ProcessorState.Started:
                return o == ProcessorState.Stopped;
            case ProcessorState.Stopped:
                return o == ProcessorState.Started;
            default: return false;
        }
    }

    override protected void onStateChanged(ProcessorState o, ProcessorState n) {
        switch(n) {
            case ProcessorState.Started:
                // creating worker threads
                foreach (ref poolThread; this.pipes) {
                    poolThread = new Pipe(&startWorkLoop);
                    poolThread.processor = this;
                    poolThread.start();
                }
                break;
            case ProcessorState.Stopped:
                if(o == ProcessorState.Started) { // stop only if it is started
                    {
                        import flow.util : atomicCasUbyte;

                        this.queueLock();
                        scope(exit) this.queueUnlock();
                        atomicCasUbyte(this.status, PoolState.running, PoolState.finishing);
                        this.notifyAll();
                    }
                    // Use this thread as a worker until everything is finished.
                    this.executeWorkLoop();

                    foreach (t; this.pipes)
                        t.join();
                }
                break;
            default:
                break;
        }
    }

    void start() {
        this.state = ProcessorState.Started;
    }

    void stop() {
        this.state = ProcessorState.Stopped;
    }

    /** This function performs initialization for each thread that affects
    thread local storage and therefore must be done from within the
    worker thread.  It then calls executeWorkLoop(). */
    private void startWorkLoop() {
        // Initialize thread index.
        {
            this.queueLock();
            scope(exit) this.queueUnlock();
            this.threadIndex = this.nextThreadIndex;
            this.nextThreadIndex++;
        }

        this.executeWorkLoop();
    }

    /** This is the main work loop that worker threads spend their time in
    until they terminate.  It's also entered by non-worker threads when
    finish() is called with the blocking variable set to true. */
    private void executeWorkLoop() {    
        import flow.util : atomicReadUbyte, atomicSetUbyte;

        while (atomicReadUbyte(this.status) != PoolState.stopNow) {
            Job* task = pop();
            if (task is null) {
                if (atomicReadUbyte(this.status) == PoolState.finishing) {
                    atomicSetUbyte(this.status, PoolState.stopNow);
                    return;
                }
            } else {
                this.doJob(task);
            }
        }
    }

    private void wait() {
        import std.datetime.systime : Clock;

        auto stdTime = Clock.currStdTime;

        // if there is nothing enqueued wait for notification
        if(this.nextTime == long.max)
            this.workerCondition.wait();
        else if(this.nextTime - stdTime > 0) // otherwise wait for schedule or notification
            this.workerCondition.wait((this.nextTime - stdTime).hnsecs);
    }

    private void notify() {
        this.workerCondition.notify();
    }

    private void notifyAll() {
        this.workerCondition.notifyAll();
    }

    private void notifyWaiters()
    {
        waiterCondition.notifyAll();
    }

    private void queueLock() {
        assert(this.queueMutex);
        this.queueMutex.lock();
    }

    private void queueUnlock() {
        assert(this.queueMutex);
        this.queueMutex.unlock();
    }

    private void waiterLock() {
        this.waiterMutex.lock();
    }

    private void waiterUnlock() {
        this.waiterMutex.unlock();
    }

    /// Pop a task off the queue.
    private Job* pop()
    {
        this.queueLock();
        scope(exit) this.queueUnlock();
        auto ret = this.popNoSync();
        while (ret is null && this.status == PoolState.running)
        {
            this.wait();
            ret = this.popNoSync();
        }
        return ret;
    }

    private Job* popNoSync()
    out(ret) {
        /* If task.prev and task.next aren't null, then another thread
         * can try to delete this task from the pool after it's
         * alreadly been deleted/popped.
         */
        if (ret !is null)
        {
            assert(ret.next is null);
            assert(ret.prev is null);
        }
    } body {
        import std.datetime.systime : Clock;

        auto stdTime = Clock.currStdTime;

        this.nextTime = long.max;
        Job* ret = this.head;
        if(ret !is null) {
            // skips ticks not to execute yet
            while(ret !is null && ret.tick.time > stdTime) {
                if(ret.tick.time < this.nextTime)
                    this.nextTime = ret.tick.time;
                ret = ret.next;
            }
        }

        if (ret !is null)
        {
            this.head = ret.next;
            ret.prev = null;
            ret.next = null;
            ret.taskStatus = JobStatus.InProgress;
        }

        if (this.head !is null)
        {
            this.head.prev = null;
        }

        return ret;
    }

    private void doJob(Job* job) {
        import flow.util : atomicSetUbyte;

        assert(job.taskStatus == JobStatus.InProgress);
        assert(job.next is null);
        assert(job.prev is null);

        scope(exit) {
            this.waiterLock();
            scope(exit) this.waiterUnlock();
            this.notifyWaiters();
        }

        try {
            job.tick.exec();
        } catch (Throwable thr) {
            job.exception = thr;
            Log.msg(LL.Fatal, "tasker failed to execute delegate", thr);
        }

        atomicSetUbyte(job.taskStatus, JobStatus.Done);
    }


    void run(string id, Tick t) {
        this.ensureState(ProcessorState.Started);

        auto j = new Job(t);
        this.abstractPut(j);
    }
    
    /// Push a task onto the queue.
    private void abstractPut(Job* task)
    {
        queueLock();
        scope(exit) queueUnlock();
        abstractPutNoSync(task);
    }

    private void abstractPutNoSync(Job* task)
    in {
        assert(task);
    } out {
        import std.conv : text;

        assert(tail.prev !is tail);
        assert(tail.next is null, text(tail.prev, '\t', tail.next));
        if (tail.prev !is null) {
            assert(tail.prev.next is tail, text(tail.prev, '\t', tail.next));
        }
    } body {
        // Not using enforce() to save on function call overhead since this
        // is a performance critical function.
        if (status != PoolState.running) {
            throw new Error(
                "Cannot submit a new task to a pool after calling " ~
                "finish() or stop()."
            );
        }

        task.next = null;
        if (head is null) {   //Queue is empty.
            head = task;
            tail = task;
            tail.prev = null;
        } else {
            assert(tail);
            task.prev = tail;
            tail.next = task;
            tail = task;
        }
        notify();
    }
}

/// represents a definded change in systems information
abstract class Tick {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import flow.data : Data;
    private import std.datetime.systime : SysTime;

    private TickMeta meta;
    private Entity entity;
    private Ticker ticker;
    private long time;

    protected @property TickInfo info() {return this.meta.info !is null ? this.meta.info.clone : null;}
    protected @property Signal trigger() {return this.meta.trigger !is null ? this.meta.trigger.clone : null;}
    protected @property TickInfo previous() {return this.meta.previous !is null ? this.meta.previous.clone : null;}
    protected @property Data data() {return this.meta.data;}

    /// lock to use for synchronizing entity context access across parallel casual strings
    protected @property ReadWriteMutex sync() {return this.entity.sync;}

    /** context of hosting entity
    warning you have to sync as reader when accessing it reading
    and as writer when accessing it writing */
    protected @property Data context() {return this.entity.meta.context;}

    /// check if execution of tick is accepted
    public @property bool accept() {return true;}

    /// predicted costs of tick (default=0)
    public @property size_t costs() {return 0;}

    /// execute tick meant to be called by processor
    package void exec() {
        import flow.util : Log;
        try {
            // run tick
            Log.msg(LL.FDebug, this.logPrefix~"running tick", this.meta);
            this.run();
            Log.msg(LL.FDebug, this.logPrefix~"finished tick", this.meta);
            
            this.ticker.actual = null;
            this.ticker.tick();
        } catch(Throwable thr) {
            Log.msg(LL.Error, this.logPrefix~"run failed", thr);
            try {
                Log.msg(LL.Info, this.logPrefix~"handling run error", thr, this.meta);
                this.error(thr);
                
                this.ticker.actual = null;        
                this.ticker.tick();
            } catch(Throwable thr2) {
                // if even handling exception failes notify that an error occured
                Log.msg(LL.Fatal, this.logPrefix~"handling error failed", thr2);
                this.ticker.actual = null;
                if(this.ticker.state != SystemState.Disposed) this.ticker.dispose;
            }
        }
    }

    /// algorithm implementation of tick
    public void run() {}

    /// exception handling implementation of tick
    public void error(Throwable thr) {}
    
    /// set next tick in causal string
    protected bool next(string tick, Data data = null) {
        return this.next(tick, Duration.init, data);
    }

    /// set next tick in causal string with delay
    protected bool next(string tick, SysTime schedule, Data data = null) {
        import std.datetime.systime : Clock;

        auto delay = schedule - Clock.currTime();

        if(delay.total!"hnsecs" > 0)
            return this.next(tick, delay, data);
        else
            return this.next(tick, data);
    }

    /// set next tick in causal string with delay
    protected bool next(string tick, Duration delay, Data data = null) {
        import std.datetime.systime : Clock;

        auto stdTime = Clock.currStdTime;
        auto t = this.entity.meta.createTickMeta(tick, this.meta.info.group).createTick(this.entity);
        if(t !is null) {
            // TODO max delay??????
            t.time = stdTime + delay.total!"hnsecs";
            t.ticker = this.ticker;
            t.meta.trigger = this.meta.trigger;
            t.meta.previous = this.meta.info;
            t.meta.data = data;

            if(t.checkAccept) {
                this.ticker.next = t;
                return true;
            } else return false;
        } else return false;
    }

    /** fork causal string by starting a new ticker
    given data will be deep cloned, since tick data has not to be synced */
    protected bool fork(string tick, Data data = null) {
        auto t = this.ticker.entity.meta.createTickMeta(tick, this.meta.info.group).createTick(this.entity);
        if(t !is null) {
            t.ticker = this.ticker;
            t.meta.trigger = this.meta.trigger;
            t.meta.previous = this.meta.info;
            t.meta.data = data;
            return this.ticker.entity.start(t);
        } else return false;
    }

    /// gets the entity controller of a given entity located in common space
    protected EntityController get(EntityPtr entity) {
        import flow.core.error : TickException;

        if(entity.space != this.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be controlled");
        else return this.get(entity.id);
    }

    private EntityController get(string e) {
        import flow.core.error : TickException;

        if(this.entity.meta.ptr.id == e)
            throw new TickException("entity cannot controll itself");
        else return this.entity.space.get(e);
    }

    /// spawns a new entity in common space
    protected EntityController spawn(EntityMeta entity) {
        return this.entity.space.spawn(entity);
    }

    /// kills a given entity in common space
    protected void kill(EntityPtr entity) {
        import flow.core.error : TickException;
        
        if(entity.space != this.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be killed");
        this.kill(entity.id);
    }

    private void kill(string e) {
        import flow.core.error : TickException;
        
        if(this.entity.meta.ptr.addr == e)
            throw new TickException("entity cannot kill itself");
        else
            this.entity.space.kill(e);
    }

    /// registers a receptor for signal which runs a tick
    protected void register(string signal, string tick) {
        import flow.core.error : TickException;
        import flow.data : createData;
        
        auto s = createData(signal).as!Signal;
        if(s is null || createData(tick) is null)
            throw new TickException("can only register receptors for valid signals and ticks");

        this.entity.register(signal, tick);
    }

    /// deregisters an receptor for signal running tick
    protected void deregister(string signal, string tick) {
        this.entity.deregister(signal, tick);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, string entity, string space) {
        auto eptr = new EntityPtr;
        eptr.id = entity;
        eptr.space = space;
        return this.send(s, eptr);
    }

    /// send an unicast signal to a destination
    protected bool send(Unicast s, EntityPtr e = null) {
        import flow.core.error : TickException;
        
        if(s is null)
            throw new TickException("cannot sand an empty unicast");

        if(e !is null) s.dst = e;

        if(s.dst is null || s.dst.id == string.init || s.dst.space == string.init)
            throw new TickException("unicast signal needs a valid destination(dst)");

        s.group = this.meta.info.group;

        return this.entity.send(s);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(T)(T s, string dst = string.init)
    if(is(T : Anycast) || is(T : Multicast)) {
        import flow.core.error : TickException;
        
        if(dst != string.init) s.dst = dst;

        if(s.dst == string.init)
            throw new TickException("anycast/multicast signal needs a space pattern");

        s.group = this.meta.info.group;

        return this.entity.send(s);
    }
}

private bool checkAccept(Tick t) {
    try {
        return t.accept;
    } catch(Throwable thr) {
        import flow.util : Log;

        Log.msg(LL.Error, t.logPrefix~"accept failed", thr);
    }

    return false;
}

/// gets the prefix string of ticks, ticker and junctions for logging
string logPrefix(T)(T t) if(is(T==Tick) || is(T==Ticker) || is(T:Junction)) {
    import std.conv : to;

    static if(is(T==Tick))
        return "tick@entity("~t.entity.meta.ptr.addr~"): ";
    else static if(is(T==Ticker))
        return "ticker@entity("~t.entity.meta.ptr.addr~"): ";
    else static if(is(T:Junction))
        return "junction("~t.meta.info.id.to!string~"): ";
}

private TickMeta createTickMeta(EntityMeta entity, string type, UUID group = randomUUID) {
    import flow.core.data : TickMeta, TickInfo;
    import std.uuid : randomUUID;

    auto m = new TickMeta;
    m.info = new TickInfo;
    m.info.id = randomUUID;
    m.info.type = type;
    m.info.entity = entity.ptr.clone;
    m.info.group = group;

    return m;
}

private Tick createTick(TickMeta m, Entity e) {
    import flow.util : as;

    if(m !is null && m.info !is null) {
        auto t = Object.factory(m.info.type).as!Tick;
        if(t !is null) {  
            t.meta = m;
            t.entity = e;
        }
        return t;
    } else return null;
}

/// executes an entitycentric string of discretized causality
private class Ticker : StateMachine!SystemState {
    bool detaching;
    
    UUID id;
    Entity entity;
    Tick actual;
    Tick next;
    Exception error;

    private this(Entity b) {
        this.id = randomUUID;
        this.entity = b;

        super();
    }

    this(Entity b, Tick initial) {
        this(b);
        this.next = initial;
        this.next.ticker = this;
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
        import core.thread : Thread;

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

    /// run next tick if possible, is usually called by a tasker
    void tick() {
        if(this.next !is null) {
            // if in ticking state try to run created tick or notify wha nothing happens
            if(this.state == SystemState.Ticking) {
                // create a new tick of given type or notify failing and stop
                if(this.next !is null) {
                    // check if entity is still running after getting the sync
                    this.actual = this.next;
                    this.next = null;
                    this.entity.space.tasker.run(this.entity.meta.ptr.addr, this.actual);
                } else {
                    Log.msg(LL.Error, this.logPrefix~"could not create tick -> ending");
                    if(this.state != SystemState.Disposed) this.dispose;
                }
            } else {
                Log.msg(LL.FDebug, this.logPrefix~"ticker is not ticking");
            }
        } else {
            Log.msg(LL.FDebug, this.logPrefix~"nothing to do, ticker is ending");
            if(this.state != SystemState.Disposed) this.dispose;
        }
    }
}

/// hosts an entity construct
private class Entity : StateMachine!SystemState {
    private import core.sync.rwmutex : ReadWriteMutex;

    /** mutex dedicated to sync context accesses */
    ReadWriteMutex sync;
    /** mutex dedicated to sync meta except context accesses */
    ReadWriteMutex metaLock;
    Space space;
    EntityMeta meta;

    Ticker[UUID] ticker;

    this(Space s, EntityMeta m) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.metaLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        m.ptr.space = s.meta.id;
        this.meta = m;
        this.space = s;

        super();
    }

    ~this() {
        if(this.state != SystemState.Disposed)
            this.dispose;
    }

    /// disposes a ticker
    void detach(Ticker t) {
        synchronized(this.lock.writer) {
            if(t.next !is null)
                synchronized(this.metaLock.writer)
                    this.meta.ticks ~= t.next.meta;
            this.ticker.remove(t.id);
        }
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
            this.freeze;

        this.state = SystemState.Disposed;
    }

    /// registers a receptor if not registered
    void register(string s, string t) {
        synchronized(this.metaLock.writer) {
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
        import std.algorithm.mutation : remove;

        synchronized(this.metaLock.writer) {
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
        synchronized(this.metaLock.writer) {
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
        import std.algorithm.mutation : remove;

        synchronized(this.metaLock.writer) {
            foreach(i, e; this.meta.events) {
                if(e.type == et && e.tick == t) {
                    this.meta.events.remove(i);
                    break;
                }
            }
        }
    }

    /// receipts a signal
    bool receipt(Signal s) {
        auto ret = false;
        Tick[] ticks;
        synchronized(this.metaLock.reader) {
            // looping all registered receptors
            foreach(r; this.meta.receptors) {
                if(s.dataType == r.signal) {
                    // creating given tick
                    auto t = this.meta.createTickMeta(r.tick, s.group).createTick(this);
                    t.meta.trigger = s;
                    ticks ~= t;
                }
            }
        }

        foreach(t; ticks)
            ret = this.start(t) || ret;
        
        return ret;
    }

    /// starts a ticker
    bool start(Tick t) {
        t.meta.info.entity = this.meta.ptr.clone; // ensuring tick belongs to us

        auto accepted = t.checkAccept;
        
        synchronized(this.lock.writer) {
            if(accepted) {
                if(this.state == SystemState.Ticking) {
                    auto ticker = new Ticker(this, t);
                    this.ticker[ticker.id] = ticker;
                    ticker.start();
                } else {
                    synchronized(this.metaLock.writer)
                        this.meta.ticks ~= t.meta;
                }   
                return true;
            }
        }

        return false;
    }

    /// send an unicast signal into own space
    bool send(Unicast s) {
        import flow.core.error : EntityException;

        synchronized(this.metaLock.reader) {
            if(s.dst == this.meta.ptr)
                new EntityException("entity cannot send signals to itself, use next or fork");

            // ensure correct source entity pointer
            s.src = this.meta.ptr;
        }

        return this.space.send(s);
    }

    /// send an anycast signal into own space
    bool send(T)(T s) 
    if(is(T : Anycast) || is(T : Multicast)) {
        synchronized(this.metaLock.reader)
            // ensure correct source entity pointer
            s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /** creates a snapshot of entity(deep clone)
    if entity is not in frozen state an exception is thrown */
    EntityMeta snap() {
        synchronized(this.metaLock.reader) {
            this.ensureState(SystemState.Frozen);
            // if someone snaps using this function, it is another entity. it will only get a deep clone.
            return this.meta.clone;
        }
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
        import std.algorithm.iteration : filter;

        switch(n) {
            case SystemState.Created:
                synchronized(this.metaLock.reader) {
                    // running onCreated ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnCreated)) {
                        auto t = this.meta.createTickMeta(e.tick).createTick(this);

                        if(t.checkAccept) {
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
                synchronized(this.metaLock.reader) {
                    // running onTicking ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnTicking)) {
                        auto t = this.meta.createTickMeta(e.tick).createTick(this);
                        if(t.checkAccept) {
                            auto ticker = new Ticker(this, t);
                            ticker.start(false);
                            ticker.join();
                            ticker.destroy();
                        }
                    }
                }

                synchronized(this.lock.writer) {
                    // creating and starting ticker for all frozen ticks
                    foreach(t; this.meta.ticks) {
                        auto ticker = new Ticker(this, t.createTick(this));
                        this.ticker[ticker.id] = ticker;
                        ticker.start();
                    }

                    // all frozen ticks are ticking -> empty store
                    this.meta.ticks = [];
                }
                break;
            case SystemState.Frozen: 
                synchronized(this.lock.writer) {
                    // stopping and destroying all ticker and freeze next ticks
                    foreach(t; this.ticker.values.dup) {
                        t.detaching = false;
                        t.stop();
                        if(t.next !is null)
                            this.meta.ticks ~= t.next.meta;
                        this.ticker.remove(t.id);
                        t.destroy();
                    }
                }

                synchronized(this.metaLock.reader) {
                    // running onFrozen ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnFrozen)) {
                        auto t = this.meta.createTickMeta(e.tick).createTick(this);
                        if(t.checkAccept) {
                            auto ticker = new Ticker(this, t);
                            ticker.start(false);
                            ticker.join();
                            ticker.destroy();
                        }
                    }
                }                    
                break;
            case SystemState.Disposed:
                synchronized(this.metaLock.reader) {
                    // running onDisposed ticks
                    foreach(e; this.meta.events.filter!(e => e.type == EventType.OnDisposed)) {
                        auto ticker = new Ticker(this, this.meta.createTickMeta(e.tick).createTick(this));
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

/// gets the string address of an entity
string addr(EntityPtr e) {
    return e.id~"@"~e.space;
}

/// controlls an entity
class EntityController {
    private import flow.data : Data;

    private Entity _entity;

    /// deep clone of entity pointer of controlled entity
    @property EntityPtr entity() {return this._entity.meta.ptr.clone;}

    /// state of entity
    @property SystemState state() {return this._entity.state;}

    /// deep clone of entity context
    @property Data context() {return this._entity.meta.context.clone;}

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

private bool matches(string id, string pattern) {
    import std.array : array;
    import std.range : split, retro, back;

    auto ip = id.split(".").retro.array;
    auto pp = pattern.split(".").retro.array;

    if(pp.length == ip.length || (pp.length < ip.length && pp.back == "*")) {
        foreach(i, p; pp) {
            if(!(p == ip[i] || (p == "*")))
                return false;
        }

        return true;
    }
    else return false;
}

unittest {
    import std.stdio : writeln;

    writeln("testing domain matching");
    assert(matches("a.b.c", "a.b.c"), "1:1 matching failed");
    assert(matches("a.b.c", "a.b.*"), "first level * matching failed");
    assert(matches("a.b.c", "a.*.c"), "second level * matching failed");
    assert(matches("a.b.c", "*.b.c"), "third level * matching failed");
}

private enum JunctionState {
    Created = 0,
    Up,
    Down,
    Disposed
}

/// allows signals from one space to get shipped to other spaces
abstract class Junction : StateMachine!JunctionState {
    private JunctionMeta _meta;
    private Space _space;
    private string[] destinations;

    protected @property JunctionMeta meta() {return this._meta;}
    protected @property string space() {return this._space.meta.id;}

    /// ctor
    this() {
        super();
    }

    private void start() {
        this.state = JunctionState.Up;
    }

    private void stop() {
        this.state = JunctionState.Down;
    }

    private void dispose() {
        if(this.state == JunctionState.Up)
            this.stop();
        
        this.state = JunctionState.Disposed;
    }

    override protected bool onStateChanging(JunctionState o, JunctionState n) {
        switch(n) {
            case JunctionState.Up:
                return o == JunctionState.Created || o == JunctionState.Down;
            case JunctionState.Down:
                return o == JunctionState.Up;
            case JunctionState.Disposed:
                return o == JunctionState.Created || o == JunctionState.Down;
            default: return false;
        }
    }

    override protected void onStateChanged(JunctionState o, JunctionState n) {        
        switch(n) {
            case JunctionState.Created:
                break;
            case JunctionState.Up:
                this.up();
                break;
            case JunctionState.Down:
                this.down();
                break;
            case JunctionState.Disposed:
                break;
            default: break;
        }
    }

    protected abstract void up();
    protected abstract void down();

    /// ship an unicast through the junction
    protected abstract bool ship(Unicast s);

    /// ship an anycast through the junction
    protected abstract bool ship(Anycast s);

    /// ship a multicast through the junction
    protected abstract bool ship(Multicast s);

    /// deliver
    protected bool deliver(T)(T s) if(is(T:Unicast) || is(T:Anycast) || is(T:Multicast)) {
        if(s.as!Unicast !is null
        || (this.meta.info.acceptsAnycast && s.as!Anycast !is null)
        || (this.meta.info.acceptsMulticast && s.as!Multicast !is null))
            return this._space.route(s, this.meta.level);
        else
            return false;
    }
}

/// hosts a space which can host n entities
class Space : StateMachine!SystemState {
    private SpaceMeta meta;
    private Process process;
    private Processor tasker;

    private Junction[] junctions;
    private Entity[string] entities;

    private this(Process p, SpaceMeta m) {
        this.meta = m;
        this.process = p;

        super();
    }

    ~this() {
        if(this.state != SystemState.Disposed)
            this.state = SystemState.Disposed;
    }

    /// makes space and all of its content freezing
    void freeze() {
        this.state = SystemState.Frozen;
    }

    /// makes space and all of its content ticking
    void tick() {
        this.state = SystemState.Ticking;
    }

    /// disposes space
    void dispose() {
        if(this.state == SystemState.Ticking)
            this.freeze();

        this.state = SystemState.Disposed;
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
            case SystemState.Created:
                import flow.core.error : SpaceException;

                // creating tasker;
                // default is one core
                if(this.meta.worker < 1)
                    this.meta.worker = 1;
                this.tasker = new Processor(this.meta.worker);
                this.tasker.start();

                // creating entities
                foreach(em; this.meta.entities) {
                    if(em.ptr.id in this.entities)
                        throw new SpaceException("entity with addr \""~em.ptr.addr~"\" already exists");
                    else {
                        // ensure entity belonging to this space
                        em.ptr.space = this.meta.id;

                        Entity e = new Entity(this, em);
                        this.entities[em.ptr.id] = e;
                    }
                }

                // creating junctions
                foreach(jm; this.meta.junctions) {
                    auto j = Object.factory(jm.type).as!Junction;
                    jm.info.space = this.meta.id; // ensure junction knows correct space
                    j._meta = jm;
                    j._space = this;
                    this.junctions ~= j;
                }
                break;
            case SystemState.Ticking:
                synchronized(this.lock.reader)
                    foreach(e; this.entities)
                        e.tick();

                foreach(j; this.junctions)
                    j.start();
                break;
            case SystemState.Frozen:
                foreach(j; this.junctions)
                    j.stop();

                synchronized(this.lock.reader)
                    foreach(e; this.entities.values)
                        e.freeze();
                break;
            case SystemState.Disposed:
                foreach(j; this.junctions) {
                    j.dispose();
                    j.destroy();
                }

                this.junctions = Junction[].init;

                synchronized(this.lock.writer)
                    foreach(e; this.entities.keys)
                        this.entities[e].destroy;

                this.tasker.stop();
                this.tasker.destroy;
                break;
            default: break;
        }
    }

    /// snapshots whole space (deep clone)
    SpaceMeta snap() {
        synchronized(this.lock.reader) {
            if(this.state == SystemState.Ticking) {
                this.state = SystemState.Frozen;
                scope(exit) this.state = SystemState.Ticking;
            }
            
            return this.meta.clone;
        }
    }

    /// gets a controller for an entity contained in space (null if not existing)
    EntityController get(string e) {
        synchronized(this.lock.reader)
            return (e in this.entities).as!bool ? new EntityController(this.entities[e]) : null;
    }

    /// spawns a new entity into space
    EntityController spawn(EntityMeta m) {
        import flow.core.error : SpaceException;

        synchronized(this.lock.writer) {
            if(m.ptr.id in this.entities)
                throw new SpaceException("entity with addr \""~m.ptr.addr~"\" is already existing");
            else {
                // ensure entity belonging to this space
                m.ptr.space = this.meta.id;
                
                this.meta.entities ~= m;
                Entity e = new Entity(this, m);
                this.entities[m.ptr.id] = e;
                return new EntityController(e);
            }
        }
    }

    /// kills an existing entity in space
    void kill(string e) {
        import flow.core.error : SpaceException;

        synchronized(this.lock.writer) {
            if(e in this.entities) {
                this.entities[e].destroy;
                this.entities.remove(e);
            } else
                throw new SpaceException("entity with addr \""~e~"\" is not existing");
        }
    }
    
    /// routes an unicast signal to receipting entities if its in this space
    private bool route(Unicast s, ushort level = 0) {
        // if its a perfect match assuming process only accepted a signal for itself
        if(this.state == SystemState.Ticking && s.dst.space == this.meta.id) {
            synchronized(this.lock.reader) {
                foreach(e; this.entities.values) {
                    if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                        if(e.meta.ptr == s.dst)
                            return e.receipt(s);
                    }
                }
            }
        }
        
        return false;
    }

   
    /// routes an anycast signal to one receipting entity
    private bool route(Anycast s, ushort level = 0) {
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        if(this.state == SystemState.Ticking) {
            synchronized(this.lock.reader) {
                foreach(e; this.entities.values) {
                    if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                        if(e.receipt(s))
                            return true;
                    }
                }
            }
        }

        return false;
    }
    
    /// routes a multicast signal to receipting entities if its addressed to space
    private bool route(Multicast s, ushort level = 0) {
        auto r = false;
        // if its adressed to own space or parent using * wildcard or even none
        // in each case we do not want to regex search when ==
        if(this.state == SystemState.Ticking) {
            synchronized(this.lock.reader) {
                foreach(e; this.entities.values) {
                    if(e.meta.level >= level) { // only accept if entities level is equal or higher the one of the junction
                        r = e.receipt(s) || r;
                    }
                }
            }
        }

        return r;
    }

    private bool send(T)(T s)
    if(is(T : Unicast)) {
        // ensure correct source space
        s.src.space = this.meta.id;

        auto isMe = s.dst.space == this.meta.id || this.meta.id.matches(s.dst.space);
        /* Only inside own space memory is shared,
        as soon as a signal is getting shiped to another space it is deep cloned */
        return isMe ? this.route(s) : this.ship(s);
    }

    private bool send(T)(T s)
    if(is(T : Anycast) || is(T : Multicast)) {
        // ensure correct source space
        s.src.space = this.meta.id;

        auto isMe = s.dst == this.meta.id || this.meta.id.matches(s.dst);
        /* Only inside own space memory is shared,
        as soon as a signal is getting shiped to another space it is deep cloned */
        return isMe ? this.route(s) : this.ship(s);
    }

    private bool ship(Unicast s) {
        foreach(j; this.junctions)
            if(j.ship(s)) return true;

        return false;
    }

    private bool ship(Anycast s) {
        foreach(j; this.junctions)
            // anycasts can only be shipped via confirming junctions
            if(j.meta.info.isConfirming && j.ship(s))
                return true;

        return false;
    }

    private bool ship(Multicast s) {
        auto ret = false;
        foreach(j; this.junctions)
            ret = j.ship(s) || ret;

        return ret;
    }
}

/** hosts one or more spaces and allows to controll them
whatever happens on this level, it has to happen in main thread or an exception occurs */
class Process {
    private import core.sync.rwmutex : ReadWriteMutex;

    private ReadWriteMutex spacesLock;
    private ReadWriteMutex junctionsLock;
    private Space[string] spaces;

    /// ctor
    this() {
        this.spacesLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.junctionsLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    ~this() {
        foreach(s; this.spaces.keys)
            this.spaces[s].destroy;
    }

    /// ensure it is executed in main thread or not at all
    private void ensureThread() {
        import flow.core.error : ProcessError;

        if(!thread_isMainThread)
            throw new ProcessError("process can be only controlled by main thread");
    }

    /// add a space
    Space add(SpaceMeta s) {   
        import flow.core.error : ProcessException;

        this.ensureThread();
        
        if(s.id in this.spaces)
            throw new ProcessException("space with id \""~s.id~"\" is already existing");
        else {
            auto space = new Space(this, s);
            synchronized(this.spacesLock.writer)
                this.spaces[s.id] = space;
            return space;
        }
    }

    /// get an existing space or null
    Space get(string s) {
        this.ensureThread();
        
        synchronized(this.spacesLock.reader)
            return (s in this.spaces).as!bool ? this.spaces[s] : null;
    }

    /// removes an existing space
    void remove(string s) {
        import flow.core.error : ProcessException;

        this.ensureThread();
        
        synchronized(this.spacesLock.writer)
            if(s in this.spaces) {
                this.spaces[s].destroy;
                this.spaces.remove(s);
            } else
                throw new ProcessException("space with id \""~s~"\" is not existing");
    }
}

version(unittest) {
    private import flow.data;

    class OldTestTickException : FlowException {mixin exception;}

    class OldTestUnicast : Unicast {
        mixin data;
    }

    class OldTestAnycast : Anycast {
        mixin data;
    }
    class OldTestMulticast : Multicast {
        mixin data;
    }

    class OldOldTestTickContext : Data {
        mixin data;

        mixin field!(bool, "gotOldTestUnicast");
        mixin field!(bool, "gotOldTestAnycast");
        mixin field!(bool, "gotOldTestMulticast");
        mixin field!(size_t, "cnt");
        mixin field!(string, "error");
        mixin field!(bool, "forked");
        mixin field!(TickInfo, "info");
        mixin field!(OldTestTickData, "data");
        mixin field!(OldTestUnicast, "trigger");
        mixin field!(bool, "onCreated");
        mixin field!(bool, "onTicking");
        mixin field!(bool, "onFrozen");
        mixin field!(bool, "timeOk");
    }

    class OldTestTickData : Data {
        mixin data;

        mixin field!(size_t, "cnt");
        mixin field!(long, "lastTime");
    }
    
    class OldTestTick : Tick {
        override void run() {
            import std.datetime.systime : Clock;

            auto stdTime = Clock.currStdTime;

            auto c = this.context.as!OldOldTestTickContext;
            auto d = this.data.as!OldTestTickData !is null ?
                this.data.as!OldTestTickData :
                "flow.core.engine.OldTestTickData".createData().as!OldTestTickData;
            auto t = this.trigger.as!OldTestUnicast;

            c.info = this.info;
            c.data = d;
            c.trigger = t;

            d.cnt++;

            c.timeOk = d.lastTime == long.init || c.timeOk && d.cnt > 4 || (c.timeOk && d.lastTime + 100.msecs.total!"hnsecs" <= stdTime);
            d.lastTime = stdTime;

            if(d.cnt == 4) {
                this.fork(this.info.type, data);
                throw new OldTestTickException;
            } else if(d.cnt > 4) {
                c.forked = true;
            } else {            
                /* we do not really need to sync that beacause D
                syncs integrals automatically but we need an example */
                synchronized(this.sync.writer)
                    c.cnt += d.cnt;

                this.next("flow.core.engine.OldTestTick", 100.msecs, d);
            }
        }

        override void error(Throwable thr) {
            if(thr.as!OldTestTickException !is null) {
                auto c = this.context.as!OldOldTestTickContext;
                synchronized(this.sync.writer)
                    c.error = thr.as!FlowException.type;
            }
        }
    }

    class UnicastReceivingOldTestTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.gotOldTestUnicast = true;

            this.next("flow.core.engine.OldTestTick");
        }
    }

    class AnycastReceivingOldTestTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.gotOldTestAnycast = true;
        }
    }

    class MulticastReceivingOldTestTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.gotOldTestMulticast = true;
        }
    }

    class OldTestOnCreatedTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.onCreated = true;
        }
    }

    class OldTestOnTickingTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.onTicking = true;
        }
    }

    class OldTestOnFrozenTick : Tick {
        override void run() {
            auto c = this.context.as!OldOldTestTickContext;
            c.onFrozen = true;
        }
    }


    class OldTriggeringTestContext : Data {
        mixin data;

        mixin field!(EntityPtr, "targetEntity");
        mixin field!(string, "targetSpace");
        mixin field!(bool, "confirmedOldTestUnicast");
        mixin field!(bool, "confirmedOldTestAnycast");
        mixin field!(bool, "confirmedOldTestMulticast");
    }

    class TriggeringOldTestTick : Tick {
        override void run() {
            auto c = this.context.as!OldTriggeringTestContext;
            c.confirmedOldTestUnicast = this.send(new OldTestUnicast, c.targetEntity);
            c.confirmedOldTestAnycast = this.send(new OldTestAnycast, c.targetSpace);
            c.confirmedOldTestMulticast = this.send(new OldTestMulticast, c.targetSpace);
        }
    }

    SpaceMeta oldCreateTestSpace() {
        auto s = new SpaceMeta;
        s.worker = 1;
        s.id = "s";
        auto te = oldCreateTestEntity();
        s.entities ~= te;
        auto tte = oldCreateTriggerTestEntity(te.ptr);
        s.entities ~= tte;

        return s;
    }

    EntityMeta oldCreateTestEntity() {
        auto e = new EntityMeta;
        e.ptr = new EntityPtr;
        e.ptr.id = "e";

        auto onc = new Event;
        onc.type = EventType.OnCreated;
        onc.tick = "flow.core.engine.OldTestOnCreatedTick";
        e.events ~= onc;
        auto ont = new Event;
        ont.type = EventType.OnTicking;
        ont.tick = "flow.core.engine.OldTestOnTickingTick";
        e.events ~= ont;
        auto onf = new Event;
        onf.type = EventType.OnFrozen;
        onf.tick = "flow.core.engine.OldTestOnFrozenTick";
        e.events ~= onf;

        auto ru = new Receptor;
        ru.signal = "flow.core.engine.OldTestUnicast";
        ru.tick = "flow.core.engine.UnicastReceivingOldTestTick";
        e.receptors ~= ru;

        auto ra = new Receptor;
        ra.signal = "flow.core.engine.OldTestAnycast";
        ra.tick = "flow.core.engine.AnycastReceivingOldTestTick";
        e.receptors ~= ra;

        auto rm = new Receptor;
        rm.signal = "flow.core.engine.OldTestMulticast";
        rm.tick = "flow.core.engine.MulticastReceivingOldTestTick";
        e.receptors ~= rm;

        e.context = new OldOldTestTickContext;

        return e;
    }

    EntityMeta oldCreateTriggerTestEntity(EntityPtr te) {
        auto e = new EntityMeta;
        e.ptr = new EntityPtr;
        e.ptr.id = "te";
        auto tc = new OldTriggeringTestContext;
        tc.targetEntity = te;
        tc.targetSpace = "s";
        e.context = tc;
        e.ticks ~= e.createTickMeta("flow.core.engine.TriggeringOldTestTick");

        return e;
    }
}

unittest {
    import std.stdio : writeln;
    import std.conv : to;
    
    writeln("testing engine (you should see exactly one \"[Error] tick@entity(e@s): run failed\" and one \"[Info] tick@entity(e@s): handling run error\" warning in log)");

    // when there is one worker in taskpool, it has
    // to be perfectly deterministic using limited complexity
    auto p = new Process();
    scope(exit) p.destroy;
    auto s = p.add(oldCreateTestSpace());
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
    auto ec = sm.entities[0].context.as!OldOldTestTickContext;
    auto tec = sm.entities[1].context.as!OldTriggeringTestContext;
    assert(sm.entities.length == 2, "space snapshot does not contain correct amount of entities");
    assert(tec.confirmedOldTestUnicast, "trigger was not correctly notified about successful unicast send");
    assert(tec.confirmedOldTestUnicast, "trigger was not correctly notified about successful anycast send");
    assert(tec.confirmedOldTestUnicast, "trigger was not correctly notified about successful multicast send");
    assert(ec.gotOldTestUnicast, "receiver didn't get test unicast");
    assert(ec.gotOldTestAnycast, "receiver didn't get test anycast");
    assert(ec.gotOldTestMulticast, "receiver didn't get test multicast");
    assert(ec.onCreated, "onCreated entity event wasn't triggered");
    assert(ec.onTicking, "onTicking entity event wasn't triggered");
    assert(ec.onFrozen, "onFrozen entity event wasn't triggered");
    assert(ec.timeOk, "delays were not respected in frame");
    assert(ec.cnt == 6, "logic wasn't executed correct, got "~ec.cnt.to!string~" instead of 6");
    assert(ec.trigger !is null, "trigger was not passed correctly");
    assert(ec.trigger.group == g, "group was not passed correctly to signal");
    assert(ec.info.group == g, "group was not passed correctly to tick");
    assert(ec.data !is null, "data was not set correctly");
    assert(ec.error == "flow.core.engine.OldTestTickException", "error was not handled");
    assert(ec.forked, "didn't fork as expected");
}