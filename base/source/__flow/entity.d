module __flow.entity;

import core.sync.rwmutex;
import std.array, std.datetime, std.uuid;
import std.algorithm.iteration, std.algorithm.searching;

import __flow.tick, __flow.type, __flow.data, __flow.process, __flow.signal;
import flow.base.dev, flow.base.interfaces, flow.base.signals, flow.base.data, flow.base.ticks;

/// generates listener meta informations to use by an entity
mixin template TListen(string s, string t)
{
    import __flow.entity;
    
    shared static this() {
        _typeListenings.add(new ListeningMeta(s, t));
    }
}

mixin template TEntity(T = void)
    if(is(T == void) || is(T : Data))
{
    import std.uuid;
    import flow.base.interfaces;
    import __flow.entity, __flow.type;
    
    private shared static List!ListeningMeta _typeListenings = new List!ListeningMeta;
    protected shared static @property List!ListeningMeta typeListenings() {
        auto l = List!ListeningMeta;
        l.add(super.typeListenings);
        l.add(_typeListenings);
        return l;
    }

    override @property string __fqn() {return fqn!(typeof(this));}

    static if(!is(T == void))
        override @property T context() {return this.meta.context.as!T;}
    else
        override @property Data context() {return this.meta.context;}

    shared static this()
    {
        Entity.register(fqn!(typeof(this)), (m){
            return new typeof(this)(m);
        });
    }
}

abstract class Entity : __IFqn, IIdentified
{
    private static Entity function()[string] _reg;

    static void register(string dataType, Entity function() creator)
	{
        _reg[dataType] = creator;
	}

	static bool canCreate(string name)
	{
		return name in _reg ? true : false;
	}

    static Entity create(EntityMeta m, Hull h)
    {
        Entity e = null;
        if(canCreate(m.info.ptr.type))
            e = _reg[m.info.ptr.type]();
        else
            e = null;
            
        if(e !is null)
            e.initialize(m, h);

        return e;
    }

    private shared static List!ListeningMeta _typeListenings = new List!ListeningMeta;
    protected static @property List!ListeningMeta typeListenings() {return _typeListenings;}

    abstract @property string __fqn();
    protected bool _shouldStop;

    private ReadWriteMutex _lock;

    protected bool _isStopped = true;
    @property bool isStopped() {return this._isStopped;}

    private bool _isSuspended = false;
    @property bool isSuspended() {return this._isSuspended;}

    private Hull _hull;
    @property Hull hull() {return this._hull;}
    
    private List!Ticker _ticker;

    private EntityMeta _meta;
    @property EntityMeta meta() {return this._meta;}

    abstract @property Data context();

    protected this() {
        this._lock = new ReadWriteMutex;
        this._ticker = new List!Ticker;
    }
    
    ~this() {
        this.stop();
    }
    
    void writeDebug(string msg, uint level) {
        debugMsg("entity("~fqnOf(this)~", "~this.id~");"~msg, level);
    }

    void initialize(EntityMeta m, Hull h) {
        if(this._isStopped)
        {
            this._meta = m;
            this._hull = h;

            // merge typeListenings and meta.listenings into meta
            auto tmpListenings = this.meta.listenings;
            foreach(tl; typeListenings) {
                auto found = false;
                foreach(ml; tmpListenings) {
                    found = tl.signal == ml.signal && tl.tick == ml.tick;
                    if(found) break;
                }

                if(!found)
                    this.meta.listenings.add(tl);
            }

            // if its not quiet react at ping
            if(this.as!IQuiet is null) {
                this.beginListen(fqn!Ping, fqn!SendPong);
                this.beginListen(fqn!UPing, fqn!SendPong);
            }

            this.start();
            this._isStopped = false;
        }
    }
    
    void start() {}

    void dispose() {
        if(!this._shouldStop && !this._isStopped)
        {
            this._shouldStop = true;
            this._listeners.clear();

            auto ticker = this._ticker.clone();
            foreach(t; ticker)
                if(t !is null)
                    t.stop();
            
            this.suspend();
            this.stop();
            this._isStopped = true;
        }
    }

    void stop() {}

    void createTicker(Signal s, string tt)
    {
        synchronized(this._lock.writer) {
            auto ti = new TickInfo;
            ti.id = randomUUID.toString();
            ti.entity = this;
            ti.type = tt;
            ti.group = s.group;
            auto ticker = new Ticker(this, s, ti, (t){this._ticker.remove(t);});
            this._ticker.add(ticker);
            ticker.start();
        }
    }

    void createTicker(TickMeta tm)
    {
        synchronized(this._lock.writer) {
            auto ticker = new Ticker(this, tm, (t){this._ticker.remove(t);});
            this._ticker.add(ticker);
            ticker.start();
        }
    }

    /// suspends the chain
    void suspend() {
        if(!this._shouldStop) synchronized(this._lock.writer)
        {
            this.writeDebug("{SUSPEND}", 3);
            this._isSuspended = true;
            foreach(t; this._ticker.clone()) {
                t.stop();
                if(t.next !is null)
                    this.meta.ticks.add(t.next);
            }
        }
    }

    /// resumes the chain
    void resume() {
        if(!this._shouldStop) {
            synchronized(this._lock.writer) {
                this.writeDebug("{RESUME}", 3);

                this._isSuspended = false;
            }
                
            // resume ticks
            foreach(tm; this.meta.ticks.clone) {
                this.createTicker(tm);
                this.meta.ticks.remove(tm);
            }
        }
    }
}