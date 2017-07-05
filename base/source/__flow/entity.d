module __flow.entity;

import core.thread, core.sync.rwmutex;
import std.array, std.datetime, std.uuid, std.conv;
import std.algorithm.iteration, std.algorithm.searching;

import __flow.process, __flow.ticker, __flow.type;
import __flow.data, __flow.signal, __flow.exception;
import flow.base.dev, flow.base.interfaces;
import flow.base.signals, flow.base.data, flow.base.ticks;

enum EntityState {
    None = 0,
    Initializing,
    Resuming,
    Running,
    Suspending,
    Suspended,
    Damaged,
    Disposing,
    Disposed
}

mixin template TEntity() {
    static import flow.base.data;
    static import __flow.entity, __flow.type, __flow.process;
    
    private shared static string[string] _typeListenings;

    public override @property string __fqn() {return __flow.type.fqn!(typeof(this));}

    shared static this() {
        __flow.entity.Entity.register(__flow.type.fqn!(typeof(this)), (__flow.process.Flow f, flow.base.data.EntityMeta m){
            return new typeof(this)(f, m);
        });
    }

    this(__flow.process.Flow f, flow.base.data.EntityMeta m) {
        string[string] typeListenings;
        
        this(f, m, typeListenings);
    }

    protected this(__flow.process.Flow f, flow.base.data.EntityMeta m, string[string] tl) {
        string[string] typeListenings;
        foreach(s; typeof(this)._typeListenings.keys)
            typeListenings[s] = typeof(this)._typeListenings[s];

        foreach(s; tl.keys)
            typeListenings[s] = tl[s];

        super(f, m, typeListenings);
    }
}

/// generates listener meta informations to use by an entity
mixin template TListen(string s, string t) {    
    shared static this() {
        _typeListenings[s] = t;
    }
}

public abstract class Entity : StateMachine!EntityState, __IFqn {
    private shared static Entity function(Flow, EntityMeta)[string] _reg;

    public static void register(string dataType, Entity function(Flow, EntityMeta) creator) {
        _reg[dataType] = creator;
	}

	package static bool canCreate(string name) {
		return name in _reg ? true : false;
	}

    package static Entity create(Flow f, EntityMeta m) {
        Entity e = null;
        if(m.info.ptr.type in _reg)
            e = _reg[m.info.ptr.type](f, m);
        else
            e = null;

        return e;
    }
    
    public abstract @property string __fqn();

    private EntityMeta _meta;
    private Entity _parent;
    private List!Entity _children;
    private string[string] _typeListenings;

    package Flow flow;
    package List!Ticker ticker;
    package List!Exception damages;
    package @property void meta(EntityMeta m) {this._meta = m;}
    package @property void parent(Entity e) {this._parent = e;}
    package @property ReadWriteMutex sync() {return this.lock;}
    package @property EntityMeta meta() {return this._meta;}

    public @property Data context() {return this._meta.context;}
    public @property Entity parent() {return this._parent;}
    public @property Entity[] children() {return this._children.array;}

    protected this(Flow f, EntityMeta m, string[string] typeListenings) {
        if(m is null || m.damages is null || !m.damages.empty)
            throw new DataDamageException("given meta data is damaged", m);

        this._typeListenings = typeListenings;
        this.flow = f;
        this.meta = m;
        this.meta.info.signals.clear();
        this._children = new List!Entity;
        this.damages = new List!Exception;
        this.ticker = new List!Ticker;

        this.state = EntityState.Initializing;
    }
    
    package void msg(DL level, string msg) {
        Debug.msg(level, "entity("~this.meta.info.ptr.type~"|"~this.meta.info.ptr.id~"@"~this.meta.info.ptr.domain~"); "~msg);
    }
    
    package void msg(DL level, Exception ex, string msg = string.init) {
        Debug.msg(level, ex, "entity("~this.meta.info.ptr.type~"|"~this.meta.info.ptr.id~"@"~this.meta.info.ptr.domain~"); "~msg);
    }

    package void msg(DL level, Data d, string msg = string.init) {
        Debug.msg(level, d, "entity("~this.meta.info.ptr.type~"|"~this.meta.info.ptr.id~"@"~this.meta.info.ptr.domain~"); "~msg);
    }

    public void suspend() {
        this.state = EntityState.Suspending;
    } 
    
    public void resume() {
        this.state = EntityState.Resuming;
    }

    public void dispose() {
        this.state = EntityState.Disposing;
    }

    public void damage(string msg = null, Exception ex = null) {
        this.msg(DL.Error, ex, msg);
        this.damages.put(ex);

        this.state = EntityState.Damaged;
    }

    public EntityMeta snap() {
        this.msg(DL.FDebug, "waiting for snap");
        synchronized(this.lock.reader) {
            this.ensureState(EntityState.Suspended);

            EntityMeta m = null;
            auto meta = this.meta.dup();
            if(meta !is null) {
                m = meta.as!EntityMeta;

                if(m is null)
                    this.damageMeta("meta of entity is of invalid type", meta);
            } else this.damageMeta("meta of entity is null");

            m = m !is null ? m : new EntityMeta;
            try {
                m.children.put(this.snapChildren());
            } catch(Exception ex) {
                this.damageMeta(ex, "snapping children failed");
            }
            
            if(!this.meta.damages.empty)
                this.damage("meta data is damaged");

            return m;
        }
    }

    public Entity spawn(EntityMeta m) {
        this.msg(DL.FDebug, "waiting for spawn");
        synchronized(this.lock.reader) {
            this.ensureState(EntityState.Running);

            return this.addChild(m);
        }
    }

    public EntityMeta kill(EntityInfo i) {
        this.msg(DL.FDebug, "waiting for kill");
        synchronized(this.lock.reader) {
            this.ensureState(EntityState.Running);

            auto e = this.flow.get(i);
            e.suspend();
            auto m = e.snap();

            // if its some child, let parent remove it
            if(e.parent !is null)
                e.parent.removeChild(e);
            else
                this.flow.remove(i);

            return m;
        }
    }

    package void tick(Signal s, string tt) {
        this.msg(DL.FDebug, "waiting for tick");
        synchronized(this.lock.reader) {
            auto ti = new TickInfo;
            ti.id = randomUUID;
            ti.entity = this.meta.info.ptr.dup();
            ti.type = tt;
            ti.group = s.group;
            auto ticker = new Ticker(this, s, ti);
            this.ticker.put(ticker);
            ticker.start();
        }
    }

    package void tick(TickMeta tm) {        
        this.msg(DL.FDebug, "waiting for tick");
        auto ticker = new Ticker(this, tm);
        this.ticker.put(ticker);
        ticker.start();
    }

    package void stopTick(Ticker t) {
        if(t.coming !is null)
            this.meta.ticks.put(t.coming);
        this.ticker.remove(t);
    }

    package bool receive(Signal s) {
        auto accepted = false;
        try {
            this.msg(DL.FDebug, "waiting for receiving");
            synchronized(this.lock.reader) {
                this.msg(DL.FDebug, "receiving");

                foreach(ms; this.meta.info.signals)
                    if(ms == s.type && this.accept(s)) {
                        if(this.state == EntityState.Running)
                            accepted = this.process(s);
                        else if(s.as!Anycast is null && (
                            this.state == EntityState.Suspending ||
                            this.state == EntityState.Suspended ||
                            this.state == EntityState.Resuming)) {
                            this.msg(DL.FDebug, "enqueuing signal");
                            // anycasts cannot be received anymore,
                            // all other signals are stored in meta
                            this.meta.inbound.put(s);
                            accepted = true;
                            break;
                        }
                    }
            }
        } catch(Exception ex) {
            this.msg(DL.Warning, ex, "receiving failed");
        }

        return accepted;
    }
    
    package bool send(Unicast s, EntityPtr e) {
        this.msg(DL.FDebug, "waiting for send");
        this._preventIdTheft(s);
        return this.state == EntityState.Running && this.flow.send(s, e);
    }

    package bool send(Unicast s, EntityInfo e) {
        return this.send(s, e.ptr);
    }

    package bool send(Unicast s) {
        this._preventIdTheft(s);
        return this.state == EntityState.Running && this.flow.send(s);
    }

    package bool send(Multicast s) {
        this._preventIdTheft(s);
        return this.state == EntityState.Running && this.flow.send(s);
    }

    package bool send(Anycast s) {
        this._preventIdTheft(s);
        return this.state == EntityState.Running && this.flow.send(s);
    }
    
    package ListeningMeta listenFor(string s, string t) {
        this.msg(DL.FDebug, "waiting for listen");
        synchronized(this.lock.reader) {
            this.ensureStateOr(EntityState.Initializing, EntityState.Running);

            auto found = false;
            foreach(ml; this.meta.listenings) {
                found = s == ml.signal && t == ml.tick;
                if(found) break;
            }

            ListeningMeta l = null;
            if(!found)
            {
                l = new ListeningMeta;
                l.signal = s;
                l.tick = t;
                this.meta.listenings.put(l);

                found = false;
                foreach(ms; this.meta.info.signals) {
                    found = ms == s;
                    if(found) break;
                }

                if(!found)
                    this.meta.info.signals.put(s);
            }

            return l;
        }
    }
    
    package void shut(ListeningMeta l) {
        this.msg(DL.FDebug, "waiting for shut");
        synchronized(this.lock.reader) {
            this.ensureStateOr(EntityState.Disposing, EntityState.Running);
            foreach(ms; this.meta.info.signals.dup())
                if(ms == l.signal) {
                    this.meta.info.signals.remove(l.signal);

                    foreach(ml; this.meta.listenings.dup())
                        if(ml == l) {
                            this.meta.listenings.remove(l);

                            if(!(l.signal in _typeListenings || (this.as!IQuiet !is null && (l.signal == fqn!Ping || l.signal == fqn!UPing))))
                                this.meta.info.signals.remove(l.signal);

                            break;
                        }

                    break;
                }
        }        
    }

    override protected bool onStateChanging(EntityState oldState, EntityState newState) {
        switch(newState) {
            case EntityState.Initializing:
                return oldState == EntityState.None;
            case EntityState.Resuming:
                return oldState == EntityState.Initializing || oldState == EntityState.Suspended;
            case EntityState.Running:
                return oldState == EntityState.Resuming;
            case EntityState.Suspending:
                return oldState == EntityState.Running;
            case EntityState.Suspended:
                return oldState == EntityState.Suspending;
            case EntityState.Damaged:
                return oldState == EntityState.Resuming ||
                    oldState == EntityState.Running ||
                    oldState == EntityState.Suspending ||
                    oldState == EntityState.Suspended;
            case EntityState.Disposing:
                return true;
            case EntityState.Disposed:
                return oldState == EntityState.Disposing;
            default:
                return false;
        }
    }

    override protected void onStateChanged(EntityState oldState, EntityState newState) {
        switch(newState) {
            case EntityState.Initializing:
                this.onInitializing(); break;
            case EntityState.Resuming:
                this.onResuming(); break;
            case EntityState.Running:
                this.onRunning(); break;
            case EntityState.Suspending:
                this.onSuspending(); break;
            case EntityState.Damaged:
                this.onDamaged(); break;
            case EntityState.Disposing:
                this.onDisposing(); break;
            default:
                break;
        }
    }

    protected void onInitializing() {
        try {
            this.msg(DL.FDebug, "waiting for initializing");
            synchronized(this.lock.reader) {
                this.msg(DL.FDebug, "initializing");
                auto type = this.meta.info.ptr.type;
                this.meta.info.ptr.flowptr = this.flow.config.ptr;
                
                this.msg(DL.FDebug, "registering type listenings");
                foreach(s; _typeListenings.keys)
                    this.meta.info.signals.put(s);

                // if its not quiet react at ping (this should be done at runtime and added to typelistenings)
                if(this.as!IQuiet is null) {
                    this.msg(DL.FDebug, "registering ping listenings");
                    this.meta.info.signals.put(fqn!Ping);
                    this.meta.info.signals.put(fqn!UPing);
                }

                this.msg(DL.FDebug, "registering dynamic listenings");
                foreach(l; this.meta.listenings)
                    this.listenFor(l.signal, l.tick);

                this.msg(DL.FDebug, "creating children entities");
                this.createChildren();
                this.meta.children.clear();
            }
        } catch(Exception ex) {
            this.damage("initializing", ex);
        }
    }

    protected void onResuming() {
        try {
            this.msg(DL.FDebug, "waiting for resuming");
            synchronized(this.lock.reader) {
                this.msg(DL.FDebug, "resuming");
                
                this.start();

                this.resumeChildren();
            }

            this.state = EntityState.Running;
        } catch(Exception ex) {
            this.damage("resuming", ex);
            return;
        }
    }

    protected void onRunning() {
        try {
            this.msg(DL.FDebug, "waiting for running");
            synchronized(this.lock.reader) {
                this.msg(DL.FDebug, "running");
                foreach(tm; this.meta.ticks.dup()) {
                    this.tick(tm);
                    this.meta.ticks.remove(tm);
                }

                this.msg(DL.FDebug, "resuming inboud signals");
                Signal s = !this.meta.inbound.empty() ? this.meta.inbound.front() : null;
                while(s !is null) {
                    this.receive(s);
                    this.meta.inbound.remove(s);
                    s = !this.meta.inbound.empty() ? this.meta.inbound.front() : null;
                }
            }
        } catch(Exception ex) {
            this.damage("resuming inboud signals", ex);
        }
    }

    protected void onSuspending() {
        try {
            this.msg(DL.FDebug, "waiting for suspending");

            // waiting for all ticker to finish
            while(!this.ticker.empty)
                Thread.sleep(WAITINGTIME);

            synchronized(this.lock.reader) {
                this.msg(DL.FDebug, "suspending");
                
                this.stop();
                
                this.suspendChildren();
            }

            this.state = EntityState.Suspended;
        } catch(Exception ex) {
            this.damage("suspending", ex);
        }
    }

    protected void onDamaged() {
        this.msg(DL.FDebug, "waiting for damaged");
        synchronized(this.lock.reader) {
            this.msg(DL.Warning, "damaged");
                
            while(!this.ticker.empty())
                Thread.sleep(WAITINGTIME);

            this.damageChildren();

            // cleanup and data rescue code here
            // try {  } catch(Throwable)  {}

            this.msg(DL.Warning, "damaged but I didn't really do anything, not implemented yet");
        }
    }

    protected void onDisposing() {
        try {
            this.msg(DL.FDebug, "waiting for disposing");
            synchronized(this.lock.writer) {
                this.msg(DL.FDebug, "disposing");
                this.disposeChildren();

                this.meta.info.signals.clear();
            }

            this.state = EntityState.Disposed;
        } catch(Exception ex) {
            this.damage("disposing", ex);
        }
    }
    
    protected void start() {}

    protected void stop() {}

    protected bool accept(Signal s) {return true;}

    private void damageMeta(string msg, Data d = null) {
        try {
                auto emd = new EntityMetaDamage;
                emd.msg = msg;
                emd.recovery = d;                
                this.meta.damages.put(emd);
        } catch(Throwable)  {}
    }
    
    private void damageMeta(Exception ex, string msg = string.init) {
        try {
            auto emd = new EntityMetaDamage;
            if(ex !is null) {
                auto m = ex.msg;

                if(msg != string.init)
                    m ~= " ["~msg~"] ";

                emd.msg = m;

                if(ex.as!FlowException)
                    emd.recovery = ex.as!FlowException.data;
            }            
            this.meta.damages.put(emd);
        } catch(Throwable)  {}
    }

    private Entity addChild(EntityMeta m) {
        auto e = this.flow.addInternal(m);
        if(e !is null) {
            e.parent = this;
            this._children.put(e);
        }

        return e;
    }

    private void removeChild(Entity e) {
        this.flow.removeInternal(e.meta.info);
        this._children.remove(e);
    }

    private void createChildren() {
        foreach(EntityMeta m; this.meta.children.dup()) {
            this.addChild(m);
        }
    }

    private void resumeChildren() {
        foreach(e; this.children.dup()) {
            if(e !is null)
                e.resume();
        }
    }

    private void suspendChildren() {
        foreach(e; this.children.dup()) {
            if(e !is null)
                e.suspend();
        }
    }

    private void damageChildren() {
        foreach(e; this.children.dup()) {
            if(e !is null)
                e.damage("parent damaged");
        }
    }

    private void disposeChildren() {
        foreach(e; this.children.dup()) {
            this.removeChild(e);
        } 
    }
    
    private DataList!EntityMeta snapChildren() {
        auto l = new DataList!EntityMeta;
        auto dmg = 0;
        foreach(e; this.children.dup()) {
            if(e !is null) {
                try {
                    l.put(e.snap());
                } catch(Exception ex) {
                    this.damageMeta(ex, "snapping child failed");
                }
            }
            else dmg = dmg + 1;
        }

        if(dmg > 0)
            this.damageMeta("found "~dmg.to!string~" null child(s)");

        return l;
    }
    
    private bool process(Signal s) {
        auto accepted = false;
        try {
            this.msg(DL.FDebug, "processing");
            
            this.msg(DL.FDebug, "processing type listenings");
            foreach(tls; _typeListenings.keys) {
                if(tls == s.type) {
                    this.tick(s, _typeListenings[tls]);
                    accepted = true;
                }
            }

            this.msg(DL.FDebug, "processing ping listenings");
            if(this.as!IQuiet is null && (s.type == fqn!Ping || s.type == fqn!UPing)) {
                this.tick(s, fqn!SendPong);
                accepted = true;
            }

            this.msg(DL.FDebug, "processing dynamic listenings");
            foreach(l; this.meta.listenings) {
                if(l.signal == s.type) {
                    this.tick(s, l.tick);
                accepted = true;
                }
            }
        } catch(Exception ex) {
            this.msg(DL.Warning, ex, "processing failed");
        }
            
        return accepted;
    }

    private void _preventIdTheft(Signal s) {
        if(this.flow.config.preventIdTheft) {
            s.source = this.meta.info.ptr.dup();
        }
    }
}