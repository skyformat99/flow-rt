module flow.core.engine;

import flow.core.util, flow.core.data;
import flow.std;

import core.thread, core.sync.rwmutex;
import std.uuid, std.string;

private enum SystemState {
    Created = 0,
    Ticking,
    Frozen,
    Disposed
}

import core.time;
import core.thread;
import core.sync.mutex;
import core.sync.condition;

package enum ProcessorState {
    Stopped = 0,
    Started
}

private enum TaskStatus : ubyte
{
    NotStarted,
    InProgress,
    Done
}

private struct Task {
    this(void delegate() j) {
        job = j;
    }

    Task* prev;
    Task* next;

    Throwable exception;
    ubyte taskStatus = TaskStatus.NotStarted;

    @property bool done()
    {
        if (atomicReadUbyte(taskStatus) == TaskStatus.Done)
        {
            if (exception)
            {
                throw exception;
            }

            return true;
        }

        return false;
    }

    void delegate() job;
}

private final class ProcessorPipe : Thread
{
    this(void delegate() dg)
    {
        super(dg);
    }

    Processor processor;
}

package final class Processor : StateMachine!ProcessorState {
    private ProcessorPipe[] pipes;
    private Space space;

    private Task* head;
    private Task* tail;
    private PoolState status = PoolState.running;
    private Condition workerCondition;
    private Condition waiterCondition;
    private Mutex queueMutex;
    private Mutex waiterMutex; // For waiterCondition

    // The instanceStartIndex of the next instance that will be created.
    __gshared static size_t nextInstanceIndex = 1;

    // The index of the current thread.
    private static size_t threadIndex;

    // The index of the first thread in this instance.
    immutable size_t instanceStartIndex;
    
    // The index that the next thread to be initialized in this pool will have.
    private size_t nextThreadIndex;

    private enum PoolState : ubyte {
        running,
        finishing,
        stopNow
    }

    this(Space spc, size_t nWorkers = 1) {
        this.space = spc;

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
        
        this.pipes = new ProcessorPipe[nWorkers];
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
                    poolThread = new ProcessorPipe(&startWorkLoop);
                    poolThread.processor = this;
                    poolThread.start();
                }
                break;
            case ProcessorState.Stopped:
                if(o == ProcessorState.Started) { // stop only if it is started
                    {
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

    // This function performs initialization for each thread that affects
    // thread local storage and therefore must be done from within the
    // worker thread.  It then calls executeWorkLoop().
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

    // This is the main work loop that worker threads spend their time in
    // until they terminate.  It's also entered by non-worker threads when
    // finish() is called with the blocking variable set to true.
    private void executeWorkLoop() {
        while (atomicReadUbyte(this.status) != PoolState.stopNow) {
            Task* task = pop();
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
        this.workerCondition.wait();
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

    // Pop a task off the queue.
    private Task* pop()
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

    private Task* popNoSync()
    out(returned)
    {
        /* If task.prev and task.next aren't null, then another thread
         * can try to delete this task from the pool after it's
         * alreadly been deleted/popped.
         */
        if (returned !is null)
        {
            assert(returned.next is null);
            assert(returned.prev is null);
        }
    }
    body
    {
        Task* returned = this.head;
        if (this.head !is null)
        {
            this.head = this.head.next;
            returned.prev = null;
            returned.next = null;
            returned.taskStatus = TaskStatus.InProgress;
        }
        if (this.head !is null)
        {
            this.head.prev = null;
        }

        return returned;
    }

    private void doJob(Task* job) {
        assert(job.taskStatus == TaskStatus.InProgress);
        assert(job.next is null);
        assert(job.prev is null);

        scope(exit) {
            this.waiterLock();
            scope(exit) this.waiterUnlock();
            this.notifyWaiters();
        }

        try {
            job.job();
        } catch (Throwable thr) {
            job.exception = thr;
            Log.msg(LL.Fatal, "tasker failed to execute delegate", thr);
        }

        atomicSetUbyte(job.taskStatus, TaskStatus.Done);
    }


    void run(string id, size_t costs, void delegate() func, Duration d = Duration.init) {
        this.ensureState(ProcessorState.Started);

        if(d == Duration.init) {
            auto tsk = new Task(func);
            this.abstractPut(tsk);
        }
        else {
            throw new NotImplementedError;
            /*synchronized(this.delayedLock) {
                auto target = MonoTime.currTime + d;
                this.delayed[target] ~= t;
            }*/
        }
    }
    
    // Push a task onto the queue.
    private void abstractPut(Task* task)
    {
        queueLock();
        scope(exit) queueUnlock();
        abstractPutNoSync(task);
    }

    private void abstractPutNoSync(Task* task)
    in
    {
        assert(task);
    }
    out
    {
        import std.conv : text;

        assert(tail.prev !is tail);
        assert(tail.next is null, text(tail.prev, '\t', tail.next));
        if (tail.prev !is null)
        {
            assert(tail.prev.next is tail, text(tail.prev, '\t', tail.next));
        }
    }
    body
    {
        // Not using enforce() to save on function call overhead since this
        // is a performance critical function.
        if (status != PoolState.running)
        {
            throw new Error(
                "Cannot submit a new task to a pool after calling " ~
                "finish() or stop()."
            );
        }

        task.next = null;
        if (head is null)   //Queue is empty.
        {
            head = task;
            tail = task;
            tail.prev = null;
        }
        else
        {
            assert(tail);
            task.prev = tail;
            tail.next = task;
            tail = task;
        }
        notify();
    }
}

abstract class Tick {    
    private TickMeta meta;
    private Entity entity;
    private Ticker ticker;

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

    /// algorithm implementation of tick
    public void run() {}

    /// exception handling implementation of tick
    public void error(Throwable thr) {}

    /// set next tick in causal string
    protected bool next(string tick, Data data = null) {
        auto t = this.entity.meta.createTickMeta(tick, this.meta.info.group).createTick(this.entity);
        if(t !is null) {
            t.ticker = this.ticker;
            t.meta.trigger = this.meta.trigger;
            t.meta.previous = this.meta.info;
            t.meta.data = data;

            if(t.checkAccept) {
                this.ticker.coming = t;
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
        if(entity.space != this.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be controlled");
        else return this.get(entity.id);
    }

    private EntityController get(string e) {
        if(this.entity.meta.ptr.id == e)
            throw new TickException("entity cannot controll itself");
        else return this.entity.space.get(e);
    }

    /// spawns a new entity in common space
    protected EntityController spawn(EntityMeta entity) {
        return this.entity.space.spawn(entity);
    }

    /// kills a given entity in common space
    protected void kill(EntityPtr
     entity) {
        if(entity.space != this.entity.space.meta.id)
            throw new TickException("an entity not belonging to own space cannot be killed");
        this.kill(entity.id);
    }

    private void kill(string e) {
        if(this.entity.meta.ptr.addr == e)
            throw new TickException("entity cannot kill itself");
        else
            this.entity.space.kill(e);
    }

    /// registers a receptor for signal which runs a tick
    protected void register(string signal, string tick) {
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
    protected bool send(Unicast signal, EntityPtr entity = null) {
        if(signal is null)
            throw new TickException("cannot sand an empty unicast");

        if(entity !is null) signal.dst = entity;

        if(signal.dst is null || signal.dst.id == string.init || signal.dst.space == string.init)
            throw new TickException("unicast signal needs a valid destination(dst)");

        signal.group = this.meta.info.group;

        return this.entity.send(signal);
    }

    /// send an anycast signal to spaces matching space pattern
    protected bool send(Anycast signal) {
        signal.group = this.meta.info.group;

        return this.entity.send(signal);
    }

    /// send a multicast signal to spaces matching space pattern
    protected bool send(Multicast signal, string space = string.init) {
        if(space != string.init) signal.space = space;

        if(signal.space == string.init)
            throw new TickException("multicast signal needs a space pattern");

        signal.group = this.meta.info.group;

        return this.entity.send(signal);
    }
}

private bool checkAccept(Tick t) {
    try {
        return t.accept;
    } catch(Throwable thr) {
        Log.msg(LL.Error, t.logPrefix~"accept failed", thr);
    }

    return false;
}

string logPrefix(T)(T t) if(is(T==Tick) || is(T==Ticker) || is(T:Junction)) {
    import std.conv;

    static if(is(T==Tick))
        return "tick@entity("~t.entity.meta.ptr.addr~"): ";
    else static if(is(T==Ticker))
        return "ticker@entity("~t.entity.meta.ptr.addr~"): ";
    else static if(is(T:Junction))
        return "junction("~t.meta.info.id.to!string~"): ";
}

TickMeta createTickMeta(EntityMeta entity, string type, UUID group = randomUUID) {
    auto m = new TickMeta;
    m.info = new TickInfo;
    m.info.id = randomUUID;
    m.info.type = type;
    m.info.entity = entity.ptr.clone;
    m.info.group = group;

    return m;
}

private Tick createTick(TickMeta m, Entity e) {
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
            if(this.coming !is null) {
                // if in ticking state try to run created tick or notify wha nothing happens
                if(this.state == SystemState.Ticking) {
                    // create a new tick of given type or notify failing and stop
                    if(this.coming !is null) {
                        // check if entity is still running after getting the sync
                        this.actual = this.coming;
                        this.coming = null;
                        this.entity.space.tasker.run(this.entity.meta.ptr.addr, this.actual.costs, &this.runTick);
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

    /// run coming tick and handle exception if it occurs
    void runTick() {
        try {
            // run tick
            Log.msg(LL.FDebug, this.logPrefix~"running tick", this.actual.meta);
            this.actual.run();
            Log.msg(LL.FDebug, this.logPrefix~"finished tick", this.actual.meta);
            
            this.actual = null;
            this.tick();
        } catch(Throwable thr) {
            Log.msg(LL.Error, this.actual.logPrefix~"run failed", thr);
            try {
                Log.msg(LL.Info, this.logPrefix~"handling run error", thr, this.actual.meta);
                this.actual.error(thr);
                
                this.actual = null;        
                this.tick();
            } catch(Throwable thr2) {
                // if even handling exception failes notify that an error occured
                Log.msg(LL.Fatal, this.actual.logPrefix~"handling error failed", thr2);
                this.actual = null;
                if(this.state != SystemState.Disposed) this.dispose;
            }
        }
    }
}

/// hosts an entity construct
private class Entity : StateMachine!SystemState {
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
            if(t.coming !is null)
                synchronized(this.metaLock.writer)
                    this.meta.ticks ~= t.coming.meta;
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
        import std.algorithm.mutation;

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
        import std.algorithm.mutation;

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
        synchronized(this.metaLock.reader) {
            if(s.dst == this.meta.ptr)
                new EntityException("entity cannot send signals to itself, use next or fork");

            // ensure correct source entity pointer
            s.src = this.meta.ptr;
        }

        return this.space.send(s);
    }

    /// send an anycast signal into own space
    bool send(Anycast s) {
        synchronized(this.metaLock.reader)
            // ensure correct source entity pointer
            s.src = this.meta.ptr;

        return this.space.send(s);
    }

    /// send a multicast signal into own space
    bool send(Multicast s) {
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
        import std.algorithm.iteration;

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
                    // stopping and destroying all ticker and freeze coming ticks
                    foreach(t; this.ticker.values.dup) {
                        t.detaching = false;
                        t.stop();
                        if(t.coming !is null)
                            this.meta.ticks ~= t.coming.meta;
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
            if(space.meta.hark && m.hit == "*")
                hit = true;
            else if(m.hit != p[i].hit)
                break;
        } else break;
    }

    return hit;
}

/// hosts a space construct
class Space : StateMachine!SystemState {
    private SpaceMeta meta;
    private Process process;
    private Processor tasker;

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

    void dispose() {
        if(this.state == SystemState.Ticking)
            this.freeze();

        this.state = SystemState.Disposed;
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
        synchronized(this.lock.writer) {
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
        synchronized(this.lock.writer) {
            if(e in this.entities) {
                this.entities[e].destroy;
                this.entities.remove(e);
            } else
                throw new SpaceException("entity with addr \""~e~"\" is not existing");
        }
    }
    
    /// routes an unicast signal to receipting entities if its in this space
    private bool route(Unicast s) {
        // if its a perfect match assuming process only accepted a signal for itself
        if(this.state == SystemState.Ticking && s.dst.space == this.meta.id) {
            synchronized(this.lock.reader) {
                foreach(e; this.entities.values)
                    if(e.meta.ptr == s.dst) {
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
        if(this.state == SystemState.Ticking && (s.space == this.meta.id || this.matches(s.space))) {
            synchronized(this.lock.reader) {
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
            synchronized(this.lock.reader) {
                foreach(e; this.entities.values)
                if(intern || e.meta.access == EntityAccess.Global)
                    e.receipt(s);
            }

            // a multicast is true if a space it could be delivered to was found
            r = true;
        }

        return r;
    }

    private bool send(Unicast s) {
        return this.route(s) || this.process.ship(s.clone);
    }

    private bool send(Anycast s) {
        return this.route(s) || this.process.ship(s.clone);
    }

    private bool send(Multicast s) {
        // ensure correct source space
        s.src.space = this.meta.id;

        /* Only inside own space memory is shared,
        as soon as a signal is getting shipd to another space it is deep cloned */
        return this.route(s, true) || this.process.ship(s.clone);
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
                // creating tasker;
                import core.cpuid;
                // if worker amount == size_t.init (0) use default (vcores - 2) but min 2
                if(this.meta.worker < 1)
                    this.meta.worker = threadsPerCPU > 3 ? threadsPerCPU-2 : 2;
                this.tasker = new Processor(this, this.meta.worker);
                this.tasker.start();

                // creating entities
                foreach(em; this.meta.entities) {
                    if(em.ptr.id in this.entities)
                        throw new SpaceException("entity with addr \""~em.ptr.addr~"\" already exists");
                    else {
                        Entity e = new Entity(this, em);
                        this.entities[em.ptr.id] = e;
                    }
                }
                break;
            case SystemState.Ticking:
                synchronized(this.lock.reader)
                    foreach(e; this.entities)
                        e.tick();
                break;
            case SystemState.Frozen:
                synchronized(this.lock.reader)
                    foreach(e; this.entities.values)
                        e.freeze();
                break;
            case SystemState.Disposed:
                synchronized(this.lock.writer)
                    foreach(e; this.entities.keys)
                        this.entities[e].destroy;

                this.tasker.stop();
                this.tasker.destroy;
                break;
            default: break;
        }
    }
}

/** hosts one or more spaces and allows to controll them
whatever happens on this level, it has to happen in main thread or an exception occurs */
class Process {
    ReadWriteMutex spacesLock;
    ReadWriteMutex junctionsLock;
    private ProcessConfig config;
    private Space[string] spaces;
    private Junction[UUID] junctions;

    this(ProcessConfig c = null) {
        this.spacesLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.junctionsLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        // if no config given generate default one
        if(c is null)
            c = new ProcessConfig;

        this.config = c;

        foreach(nm; this.config.junctions) {
            try {
                this.add(nm);
            } catch(Throwable thr) {
                Log.msg(LL.Error, "initialization of a net at process startup failed", thr);
            }
        }
    }

    ~this() {
        foreach(s; this.spaces.keys)
            this.spaces[s].destroy;
    }

    @property string[] acceptedSpaces() {
        import std.algorithm.iteration, std.array;

        synchronized(this.spacesLock.reader)
            return this.spaces.values
                .filter!(s=>s !is null && s.meta !is null && s.meta.hark)
                .map!(s=>s.meta.id).array;
    }

    /// adds a junction to process
    void add(JunctionMeta m) {
        import std.conv;

        this.ensureThread();
        
        if(m is null || m.info is null || m.info.id == UUID.init)
            throw new ProcessException("invalid net metadata", m);

        Log.msg(LL.Info, "initializing junction with id \""~m.info.id.to!string~"\"");

        if(m.info.id in this.junctions)
            throw new ProcessException("a junction with id \""~m.info.id.to!string~"\" already exists", m);

        if(m.as!DynamicJunctionMeta !is null)
            synchronized(this.junctionsLock.writer)
                this.junctions[m.info.id] = new DynamicJunction(this, m.as!DynamicJunctionMeta);
        else {
            Log.msg(LL.Error, "not supporting junction type", m);
            throw new NotImplementedError;
        }
    }

    /// removes a junction from process
    void remove(UUID id) {
        import std.conv;

        this.ensureThread();
        
        synchronized(this.junctionsLock.writer)
            if(id in this.junctions) {
                Junction j = this.junctions[id];
                this.junctions.remove(id);
                j.destroy;
            } else throw new ProcessException("no junction with id \""~id.to!string~"\" found for removal");
    }

    /// routing unicast signal from space to space also across nets
    private bool ship(Unicast s) {
        if(s !is null) {
            foreach(spc; this.spaces.values)
                if(s.src.space != spc.meta.id && s.dst.space == spc.meta.id)
                    return spc.route(s);

            synchronized(this.junctionsLock.reader) {
                // when here, its not hosted in local process so ship it to process hosting its space if known
                // block until acceptance is confirmed by remote process
            }
        }
        
        return false;
    }

    /// routing anycast signal from space to space also across nets
    private bool ship(Anycast s) {
        if(s !is null) {
            foreach(spc; this.spaces.values)
                if(s.src.space != spc.meta.id && spc.route(s))
                    return true;

            synchronized(this.junctionsLock.reader) {
                // when here, no local space matches space pattern so ship it to processes hosting spaces matching
                // block until acceptance is confirmed by remote process
            }
        }
        
        return false;
    }

    /// routing multicast signal from space to space also across nets
    private bool ship(Multicast s) {
        auto r = false;
        if(s !is null) {
            foreach(spc; this.spaces.values)
                if(s.src.space != spc.meta.id)
                    r = spc.route(s) || r;
        }

        synchronized(this.junctionsLock.reader) {
            // signal might target other spaces hosted by remote processes too, so ship it to all processes hosting spaces matching pattern
            // not blocking, just (is proccess with matching space known) || r
            /* that means multicasts are returning true if an adequate space is known local or remote,
            this is neccessary due to the requirement for flow to support systems interconnected by
            huge latency lines. an extreme case could be the connection between spaces sparated by lightyears. */
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
        this.ensureThread();
        
        synchronized(this.spacesLock.writer)
            if(s in this.spaces) {
                this.spaces[s].destroy;
                this.spaces.remove(s);
            } else
                throw new ProcessException("space with id \""~s~"\" is not existing");
    }
}

private enum JunctionState {
    Created = 0,
    Up,
    Down,
    Disposed
}

private abstract class Junction : StateMachine!JunctionState {
    ReadWriteMutex connectionsLock;
    Process process;
    JunctionMeta meta;
    Listener listener;
    Connection[] connections;

    this(Process p, JunctionMeta m) {
        this.connectionsLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.process = p;
        this.meta = m;

        super();
    }

    void up() {
        this.state = JunctionState.Up;
    }

    void down() {
        this.state = JunctionState.Down;
    }

    void dispose() {
        if(this.state == JunctionState.Up)
            this.down;
        
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
                if(this.meta.listener.as!InetListenerMeta)
                    this.listener = new InetListener(this.meta.listener.as!InetListenerMeta);
                else if(this.meta.listener !is null)
                    Log.msg(LL.Error, this.logPrefix~"unknown listener type, won't create any for this junction", this.meta.listener);
                break;
            case JunctionState.Up:
                if(this.listener !is null)
                    this.listener.start;

                // establish outbound connections
                synchronized(this.connectionsLock.writer)
                    foreach(ci; this.meta.connections) {
                        // only if its an outbound connection
                        if(ci != this.listener.meta.info) {
                            if(ci.as!InetListenerInfo) {
                                auto c = ci.as!InetListenerInfo.connect;
                                if(c !is null) {
                                    this.connections ~= c;
                                    c.start;
                                }
                            }
                        }
                    }
                break;
            case JunctionState.Down:
                if(this.listener !is null)
                    this.listener.stop;

                // disconnect existing connections and add outbound to meta
                synchronized(this.connectionsLock.writer) {
                    this.meta.connections = [];
                    foreach(c; this.connections) {
                        c.stop;
                        if(!c.incoming)
                            this.meta.connections ~= c.peer.listener;
                        c.destroy;
                    }
                }
                break;
            case JunctionState.Disposed:
                this.listener.destroy;
                break;
            default: break;
        }
    }

    void route(T)(T s) if(is(T : Signal)) {
        static if(is(T == ForwardRequest)) {
            // TODO has to execute a task in junction taskpool
            // TODO check if can and want to forward (FIREWALL HOOK)
        } else static if(is(T : Unicast) || is(T : Anycast) || is(T : Multicast)) {
            this.process.ship(s);
        } else {
            Log.msg(LL.Warning, this.logPrefix~"unknown signal type", s);
        }
    }
}

private class DynamicJunction : Junction {
    this(Process p, DynamicJunctionMeta m) {super(p, m);}
}

private abstract class Listener {
    ListenerMeta meta;

    this(ListenerMeta m) {
        this.meta = m;
    }

    abstract void start();
    abstract void stop();
}

private class InetListener : Listener {
    this(InetListenerMeta m) {super(m);}

    override void start() {

    }

    override void stop() {

    }
}

private class Connection : Thread {
    import std.socket;
    import core.sync.rwmutex;

    Junction junction;
    PeerInfo peer;
    ReadWriteMutex lock;
    bool alive;
    bool incoming;

    Socket inbound;
    Socket outbound;

    @property PeerInfo info() {
        auto pi = new PeerInfo;
        pi.junction = this.junction.meta.info;
        pi.listener = this.junction.listener.meta.info;
        return pi;
    }

    this(Junction j, Socket i, Socket o, bool inc) {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.junction = j;
        this.inbound = i;
        this.outbound = o;
        this.incoming = inc;

        super(&this.loop);
    }

    ~this() {
        this.stop;
    }

    void loop() {
        ubyte[] arr;
        size_t act;
        size_t received;
        ubyte[4096] buffer;

        synchronized(this.lock.reader) {
            // setting beeing alive
            this.alive = true;

            // authenticating with peer
            this.send(this.info);
        }

        while(true) {
            synchronized(this.lock.reader)
                if(this.alive && this.inbound.isAlive) {
                    try {
                        import std.range.primitives;
                        import std.bitmanip;
                        auto c = this.inbound.receive(buffer);

                        // if something received, append it to inbound array
                        if(c > 0) {
                            arr ~= buffer[0..c];
                            received += c;
                        }

                        if(act == 0 && received > 0) { // beginning new packet
                            act = arr[0..size_t.sizeof].bigEndianToNative!size_t;
                            arr.popFrontN(size_t.sizeof);
                        } else if(act > 0 && act < received) { // if packet is complete
                            auto b = arr[0..act];
                            auto d = b.unbin!Data;
                            arr.popFrontN(act);

                            if(d.as!PeerInfo !is null) { // peer authentications or updates
                                if(!this.authenticate(d.as!PeerInfo))
                                    break;
                            } else if(d.as!Signal) // peer signals through junction
                                this.junction.route(d.as!Signal);
                            else
                                Log.msg(LL.Warning, this.junction.logPrefix~"received unknown information", d);

                            act = 0;
                        } // else wait for data so loop
                    } catch(Throwable thr) {
                        Log.msg(LL.Error, this.junction.logPrefix~"error occured at listening to inbound data", thr, this.info);
                        break;
                    }
                } else break;
        }

        // if not died because of this.alive (stop) then clean up
        this.stop;
    }

    bool authenticate(PeerInfo pi) {
        if(!this.junction.meta.info.validation || this.validate(pi)) {
            this.peer = pi;
            return true;
        } else return false;
    }

    bool validate(PeerInfo pi) {
        /* TODO check certificate
        ((is it the same || if unknown yet does it validate with a known authority) &&
        does it validate its own signature?)
        * this has to happen also on update to prevent connection highjacking
        * all packages sent have to be signed to prevent connection highjacking*/

        return true;
    }

    void stop() {
        synchronized(this.lock.writer) 
            if(this.alive) {
                this.alive = false;
                this.peer = null;
                
                this.inbound.close;
                this.inbound = null;

                this.outbound.close;
                this.outbound = null;
            }
    }

    void send(Data d) {
        import std.bitmanip;
        synchronized(this.lock.reader)
            if(this.alive && this.outbound.isAlive) {
                auto b = d.bin;
                this.outbound.send(b.length.nativeToBigEndian[]);
                this.outbound.send(b);
            }
    }
}

private Connection connect(T)(T li) if(is(T == InetListenerInfo)) {
    // TODO
    return null;
}

/*struct SpaceHop {
    Duration latency;
    ubyte[] cert;
}

struct SpaceRoute {
    string id;
    SpaceHop[] hops;
}

private abstract class Peer {
    import core.thread;

    Process process;
    PeerMeta meta;
    PeerInfo other;
    Thread receivingThread;

    bool connected;

    @property PeerInfo self() {
        auto i = new PeerInfo;
        i.forward = this.meta.forward;
        i.spaces = this.process.acceptedSpaces;

        return i;
    }

    protected this() {
        receivingThread = new Thread(&this.receiving);
        receivingThread.start();
    }

    void receiving() {
        this.connected = true;

        Data d;
        do {
            d = this.receive();
        } while(this.connected);
    }

    this(Process p, PeerMeta m) {
        this.process = p;
        this.meta = m;

        this.connect;
    }

    ~this() {
        this.disconnect;
    }    

    abstract Data receive();
    abstract void connect();
    abstract void disconnect();
}

private class InetPeer : Peer {
    Socket sock;

    this(Process p, PeerMeta m) {super(p, m);}
    this(Socket s) {
        super();
    }

    override void connect() {

    }

    override void disconnect() {

    }
}*/

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
        import flow.core.util;

        override void run() {
            auto c = this.context.as!TestTickContext;
            auto d = this.data.as!TestTickData !is null ?
                this.data.as!TestTickData :
                "flow.core.engine.TestTickData".createData().as!TestTickData;
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

                this.next("flow.core.engine.TestTick", d);
            }
        }

        override void error(Throwable thr) {
            if(thr.as!TestTickException !is null) {
                auto c = this.context.as!TestTickContext;
                synchronized(this.sync.writer)
                    c.error = thr.as!FlowException.type;
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
        s.worker = 1;
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
        onc.tick = "flow.core.engine.TestOnCreatedTick";
        e.events ~= onc;
        auto ont = new Event;
        ont.type = EventType.OnTicking;
        ont.tick = "flow.core.engine.TestOnTickingTick";
        e.events ~= ont;
        auto onf = new Event;
        onf.type = EventType.OnFrozen;
        onf.tick = "flow.core.engine.TestOnFrozenTick";
        e.events ~= onf;

        auto r = new Receptor;
        r.signal = "flow.core.engine.TestSignal";
        r.tick = "flow.core.engine.TestTick";
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
        e.ticks ~= e.createTickMeta("flow.core.engine.TriggeringTestTick");

        return e;
    }
}

unittest {
    import std.stdio, std.conv;
    writeln("testing engine (you should see exactly one \"tick failed\" warning in log)");

    auto pc = new ProcessConfig;
    /* when there is one worker in taskpool, it has
    to be perfectly deterministic using limited complexity */
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
    assert(sm.entities[0].context.as!TestTickContext.error == "flow.core.engine.TestTickException", "error was not handled");
    assert(sm.entities[0].context.as!TestTickContext.forked, "didn't fork as expected");
}