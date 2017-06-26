module __flow.entity;

import core.thread, core.sync.rwmutex;
import std.array, std.datetime, std.uuid, std.conv;
import std.algorithm.iteration, std.algorithm.searching;

import __flow.process, __flow.ticker, __flow.type;
import __flow.data, __flow.signal, __flow.exception;
import flow.base.dev, flow.base.interfaces;
import flow.base.signals, flow.base.data, flow.base.ticks;

void debugMsg(Entity e, DL level, string msg = string.init, Exception ex = null) {
    Debug.msg(level, "entity("~e.info.ptr.type~"|"~e.address~"); "~msg, ex);
}

/// generates listener meta informations to use by an entity
mixin template TListen(string s, string t) {
    import __flow.entity;
    
    shared static this() {
        _typeListenings[s] = t;
    }
}

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

mixin template TEntity(T = void) if(is(T == void) || is(T : Data)) {
    import std.uuid;
    import flow.base.data;
    import __flow.entity, __flow.type;
    
    private shared static string[string] _typeListenings;

    public override @property string __fqn() {return fqn!(typeof(this));}

    static if(!is(T == void))
        public override @property T context() {return this._meta.context.as!T;}
    else
        public override @property Data context() {return this._meta.context;}

    shared static this() {
        Entity.register(fqn!(typeof(this)), (){
            return new typeof(this)();
        });
    }
}

abstract class Entity : StateMachine!EntityState, __IFqn {
    private shared static Entity function()[string] _reg;    
    private shared static string[string] _typeListenings;

    public static void register(string dataType, Entity function() creator) {
        _reg[dataType] = creator;
	}

	public static bool canCreate(string name) {
		return name in _reg ? true : false;
	}

    public static Entity create(string name) {
        Entity e = null;
        if(name in _reg)
            e = _reg[name]();
        else
            e = null;

        return e;
    }
    
    private Entity _parent;
    private Flow _flow;
    private List!Exception _damages;
    private List!Ticker _ticker;
    private EntityMeta _meta;

    package List!Entity _children;
    package @property bool tracing() { return this._flow.config.tracing; }

    public abstract @property string __fqn();
    public @property EntityInfo info() { return this._meta.info.dup(); }
    public @property string address() { return this._meta.info.ptr.id~"@"~this._meta.info.ptr.domain; }
    public @property List!Exception damges() { return this._damages.dup(); }
    public abstract @property Data context();

    protected this(Flow f, EntityMeta m) {
        if(m is null || m.damages is null || !m.damages.empty)
            throw new DataDamageException("given meta data is damaged", m);

        this._flow = f;
        this._meta = m;
        this._meta.info.signals.clear();
        this._children = new List!Entity;
        this._damages = new List!Exception;
        this._ticker = new List!Ticker;

        this.state = EntityState.Initializing;
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
        this.debugMsg(DL.Warning, msg, ex);
        this._damages.put(ex);

        this.state = EntityState.Damaged;
    }

    public void tick(Signal s, string tt) {
        this.debugMsg(DL.Debug, "tick waiting");
        synchronized(this.lock.reader) {
            auto ti = new TickInfo;
            ti.id = randomUUID;
            ti.entity = this._meta.info.ptr.dup();
            ti.type = tt;
            ti.group = s.group;
            auto ticker = new Ticker(this, s, ti, (t){this._ticker.remove(t);});
            this._ticker.put(ticker);
            ticker.start();
        }
    }

    public void tick(TickMeta tm) {        
        this.debugMsg(DL.Debug, "tick waiting");
        synchronized(this.lock.reader) {
            auto ticker = new Ticker(this, tm, (t){this._ticker.remove(t);});
            this._ticker.put(ticker);
            ticker.start();
        }
    }

    public bool receive(Signal s) {
        auto accepted = false;
        try {
            this.debugMsg(DL.Debug, "receiving waiting");
            synchronized(this.lock.reader) {                
                this.debugMsg(DL.Info, "receiving");

                foreach(ms; this._meta.info.signals)
                    if(ms == s.type) {
                        if(this.state == EntityState.Running)
                            accepted = this.process(s);
                        else if(s.as!Anycast is null && (
                            this.state == EntityState.Suspending ||
                            this.state == EntityState.Suspended ||
                            this.state == EntityState.Resuming)) {
                            this.debugMsg(DL.Debug, "enqueuing signal");
                            // anycasts cannot be received anymore,
                            // all other signals are stored in meta
                            this._meta.inbound.put(s);
                            accepted = true;
                            break;
                        }
                    }
            }
        } catch(Exception ex) {
            this.debugMsg(DL.Warning, "receiving", ex);
        }

        return accepted;
    }
    
    public bool send(Unicast s, EntityPtr e) {
        this.debugMsg(DL.Debug, "send waiting");
        synchronized(this.lock.reader) {
            this._preventIdTheft(s);
            return this._flow.send(s, e);
        }
    }

    public bool send(Unicast s, EntityInfo e) {
        return this.send(s, e.ptr);
    }

    public bool send(Unicast s) {
        this.debugMsg(DL.Debug, "send waiting");
        synchronized(this.lock.reader) {
            this._preventIdTheft(s);
            return this._flow.send(s);
        }
    }

    public bool send(Multicast s) {
        this.debugMsg(DL.Debug, "send waiting");
        synchronized(this.lock.reader) {
            this._preventIdTheft(s);
            return this._flow.send(s);
        }
    }

    public bool send(Anycast s) {
        this.debugMsg(DL.Debug, "send waiting");
        synchronized(this.lock.reader) {
            this._preventIdTheft(s);
            return this._flow.send(s);
        }
    }
    
    public ListeningMeta listen(string s, string t) {
        this.debugMsg(DL.Debug, "listen waiting");
        synchronized(this.lock.reader) {
            this.ensureStateOr([EntityState.Initializing, EntityState.Running]);

            auto found = false;
            foreach(ml; this._meta.listenings) {
                found = s == ml.signal && t == ml.tick;
                if(found) break;
            }

            ListeningMeta l = null;
            if(!found)
            {
                l = new ListeningMeta;
                l.signal = s;
                l.tick = t;
                this._meta.listenings.put(l);

                found = false;
                foreach(ms; this._meta.info.signals) {
                    found = ms == s;
                    if(found) break;
                }

                if(!found)
                    this._meta.info.signals.put(s);
            }

            return l;
        }
    }
    
    public void shut(ListeningMeta l) {
        this.debugMsg(DL.Debug, "shut waiting");
        synchronized(this.lock.reader) {
            this.ensureStateOr([EntityState.Disposing, EntityState.Running]);
            foreach(ms; this._meta.info.signals.dup())
                if(ms == l.signal) {
                    this._meta.info.signals.remove(l.signal);

                    foreach(ml; this._meta.listenings.dup())
                        if(ml == l) {
                            this._meta.listenings.remove(l);

                            if(!(l.signal in _typeListenings || (this.as!IQuiet !is null && (l.signal == fqn!Ping || l.signal == fqn!UPing))))
                                this._meta.info.signals.remove(l.signal);

                            break;
                        }

                    break;
                }
        }        
    }

    public EntityMeta snap() {
        this.debugMsg(DL.Debug, "snap waiting");
        synchronized(this.lock.reader) {
            this.ensureState(EntityState.Suspended);

            EntityMeta m = null;
            auto meta = this._meta.dup();
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
            
            return m;
        }
    }

    public bool spawn(EntityMeta m) {
        this.debugMsg(DL.Debug, "listen waiting");
        synchronized(this.lock.reader) {
            this.ensureState(EntityState.Running);

            return this.addChild(m);
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
        synchronized(this.lock.writer)
            switch(newState) {
                case EntityState.Initializing:
                    this.onInitializing(); break;
                case EntityState.Resuming:
                    this.onResuming(); break;
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
            this.debugMsg(DL.Debug, "initializing waiting");
            synchronized(this.lock.reader) {
                this.debugMsg(DL.Info, "initializing");
                auto type = this._meta.info.ptr.type;
                this._meta.info.ptr.flowptr = this._flow.config.ptr;
                
                this.debugMsg(DL.Debug, "registering type listenings");
                foreach(s; _typeListenings.keys)
                    this._meta.info.signals.put(s);

                // if its not quiet react at ping (this should be done at runtime and added to typelistenings)
                if(this.as!IQuiet is null) {
                    this.debugMsg(DL.Debug, "registering ping listenings");
                    this._meta.info.signals.put(fqn!Ping);
                    this._meta.info.signals.put(fqn!UPing);
                }

                this.debugMsg(DL.Debug, "registering dynamic listenings");
                foreach(l; this._meta.listenings)
                    this.listen(l.signal, l.tick);

                this.debugMsg(DL.Debug, "creating children entities");
                this.createChildren();
                this._meta.children.clear();
            }

            this.state = EntityState.Resuming;
        } catch(Exception ex) {
            this.damage("initializing", ex);
        }
    }

    protected void onResuming() {
        try {
            this.debugMsg(DL.Debug, "resuming waiting");
            synchronized(this.lock.reader) {
                this.debugMsg(DL.Info, "resuming");
                
                this.start();

                this.resumeChildren();

                foreach(tm; this._meta.ticks.dup()) {
                    this.tick(tm);
                    this._meta.ticks.remove(tm);
                }
            }

            this.state = EntityState.Running;
        } catch(Exception ex) {
            this.damage("resuming", ex);
            return;
        }

        try {
            this.debugMsg(DL.Debug, "resuming inbound signals waiting");
            synchronized(this.lock.reader) {
                if(this.state == EntityState.Running) {
                    this.debugMsg(DL.Info, "resuming inboud signals");
                    Signal s = !this._meta.inbound.empty() ? this._meta.inbound.front() : null;
                    while(s !is null) {
                        this.receive(s);
                        this._meta.inbound.remove(s);
                        s = !this._meta.inbound.empty() ? this._meta.inbound.front() : null;
                    }
                }
            }
        } catch(Exception ex) {
            this.damage("resuming inboud signals", ex);
        }
    }

    protected void onSuspending() {
        try {
            this.debugMsg(DL.Debug, "suspending waiting");
            synchronized(this.lock.reader) {
                this.debugMsg(DL.Info, "suspending");

                this._meta.ticks.clear();
                
                while(!this._ticker.empty())
                    Thread.sleep(WAITINGTIME);

                this.stop();
                
                this.suspendChildren();
            }

            this.state = EntityState.Suspended;
        } catch(Exception ex) {
            this.damage("suspending", ex);
        }
    }

    protected void onDamaged() {
        this.debugMsg(DL.Debug, "damaged waiting");
        synchronized(this.lock.reader) {
            this.debugMsg(DL.Warning, "damaged");
                
            while(!this._ticker.empty())
                Thread.sleep(WAITINGTIME);

            this.damageChildren();

            // cleanup and data rescue code here
            // try {  } catch(Throwable)  {}

            this.debugMsg(DL.Warning, "damaged but I didn't really do anything, not implemented yet");
        }
    }

    protected void onDisposing() {
        try {
            this.debugMsg(DL.Debug, "disposing waiting");
            synchronized(this.lock.reader) {
                this.debugMsg(DL.Info, "disposing");
                this.disposeChildren();

                this._meta.info.signals.clear();
            }

            this.state = EntityState.Disposed;
        } catch(Exception ex) {
            this.damage("disposing", ex);
        }
    }
    
    protected void start() {}

    protected void stop() {}

    private void damageMeta(string msg, Data d = null) {
        try {
                auto emd = new EntityMetaDamage;
                emd.msg = msg;
                emd.recovery = d;                
                this._meta.damages.put(emd);
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
            this._meta.damages.put(emd);
        } catch(Throwable)  {}
    }

    private bool addChild(EntityMeta m) {
        auto e = this._flow.addInternal(m);
        if(e !is null) {
            e._parent = this;
            this._children.put(e);
            return true;
        } else return false;
    }

    private void removeChild(Entity e) {
        this._flow.removeInternal(e.info);
        this._children.remove(e);
    }

    private void createChildren() {
        foreach(EntityMeta m; this._meta.children.dup()) {
            this.addChild(m);
        }
    }

    private void resumeChildren() {
        foreach(e; this._children.dup()) {
            if(e !is null)
                e.resume();
        }
    }

    private void suspendChildren() {
        foreach(e; this._children.dup()) {
            if(e !is null)
                e.suspend();
        }
    }

    private void damageChildren() {
        foreach(e; this._children.dup()) {
            if(e !is null)
                e.damage("parent damaged");
        }
    }

    private void disposeChildren() {
        foreach(e; this._children.dup()) {
            this.removeChild(e);
        } 
    }
    
    private DataList!EntityMeta snapChildren() {
        auto l = new DataList!EntityMeta;
        auto dmg = 0;
        foreach(e; this._children.dup()) {
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
            this.debugMsg(DL.Info, "processing");
            
            this.debugMsg(DL.Debug, "processing type listenings");
            foreach(tls; _typeListenings.keys) {
                if(tls == s.type) {
                    this.tick(s, _typeListenings[tls]);
                    accepted = true;
                }
            }

            this.debugMsg(DL.Debug, "processing ping listenings");
            if(this.as!IQuiet is null && (s.type == fqn!Ping || s.type == fqn!UPing)) {
                this.tick(s, fqn!SendPong);
                accepted = true;
            }

            this.debugMsg(DL.Debug, "processing dynamic listenings");
            foreach(l; this._meta.listenings) {
                if(l.signal == s.type) {
                    this.tick(s, l.tick);
                accepted = true;
                }
            }
        } catch(Exception ex) {
            this.debugMsg(DL.Warning, "processing", ex);
        }
            
        return accepted;
    }

    private void _preventIdTheft(Signal s) {
        if(this._flow.config.preventIdTheft) {
            s.source = this._meta.info.ptr.dup();
        }
    }
}