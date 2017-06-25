module __flow.entity;

import core.sync.rwmutex;
import std.array, std.datetime, std.uuid;
import std.algorithm.iteration, std.algorithm.searching;

import __flow.tick, __flow.type, __flow.data, __flow.process, __flow.signal;
import flow.base.dev, flow.base.interfaces, flow.base.signals, flow.base.data, flow.base.ticks;

/// generates listener meta informations to use by an entity
mixin template TListen(string s, string t) {
    import __flow.entity;
    import flow.base.data;
    
    shared static this() {
        auto m = new ListeningMeta;
        m.signal = s;
        m.tick = t;
        _typeListenings[s] ~= t;
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

    package override @property string __fqn() {return fqn!(typeof(this));}

    static if(!is(T == void))
        package override @property T context() {return this.meta.context.as!T;}
    else
        package override @property Data context() {return this.meta.context;}

    shared static this() {
        Entity.register(fqn!(typeof(this)), (){
            return new typeof(this)();
        });
    }
}

abstract class Entity : StateMachine!EntityState, __IFqn {
    private shared static Entity function()[string] _reg;    
    private shared static string[string] _typeListenings;

    package static void register(string dataType, Entity function() creator) {
        _reg[dataType] = creator;
	}

	package static bool canCreate(string name) {
		return name in _reg ? true : false;
	}

    package static Entity create(string name) {
        Entity e = null;
        if(canCreate(name))
            e = _reg[name]();
        else
            e = null;

        return e;
    }

    
    private Entity _parent;
    private List!Entity _children;
    private Flow _flow;
    private ReadWriteMutex _lock;    
    private List!Exception _damage;
    private List!Ticker _ticker;
    private EntityMeta _meta;

    package abstract @property string __fqn();
    package @property ReadWriteMutex lock() {return this._lock;}
    package @property string address() { return this.info.ptr.id~"@"~this.info.ptr.domain; }
    package @property bool tracing() { return this._flow.config.tracing; }
    package abstract @property Data context();

    public @property FlowPtr flow() { return this._flow.ptr; }
    public @property EntityInfo info() { return this._entity.meta.info; }

    protected this(Flow f, EntityMeta m) {
        this._flow = f;
        this._meta = m;
        this.info.signals.clear();
        this._children = new List!Entity;
        this._lock = new ReadWriteMutex;
        this._damage = new List!Exception;
        this._ticker = new List!Ticker;

        this.state = EntityState.Initializing;
    }
    
    ~this() {
        this.stop();
    }

    package void suspend() {
        this.state = EntityState.Suspending;
    } 
    
    package void resume() {
        this.state = EntityState.Resuming;
    }

    package void dispose() {
        this.state = EntityState.Disposing;
    }

    package void damage(string msg = null, Exception ex = null) {
        this.debugMsg(DL_WARNING, msg, ex);
        this._damage.put(ex);

        this.state = EntityState.Damaged;
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
            this.debugMsg(DL_INFO, "initializing");
            auto type = this._meta.info.ptr.type;
            this._meta.info.ptr.flowptr = this.flowptr;
            
            this.debugMsg(DL_DEBUG, "registering type listenings");
            foreach(s; _typeListenings.keys)
                this.beginListen(s);

            // if its not quiet react at ping (this should be done at runtime and added to typelistenings)
            if(this.as!IQuiet is null) {
                this.debugMsg(DL_DEBUG, "registering ping listenings");
                this.beginListen(fqn!Ping);
                this.beginListen(fqn!UPing);
            }

            this.debugMsg(DL_DEBUG, "registering dynamic listenings");
            foreach(l; this._meta.listenings)
                this.beginListen(l.signal);

            this.debugMsg(DL_DEBUG, "creating children entities");
            this.createChildren();

            this.state = EntityState.Resuming;
        } catch(Exception ex) {
            this.damage("initializing", ex);
        }
    }

    protected void onResuming() {
        try {
            this.debugMsg(DL_INFO, "resuming");
            
            this.start();

            this.resumeChildren();

            foreach(tm; this.meta.ticks.dup()) {
                this.createTicker(tm);
                this.meta.ticks.remove(tm);
            }

            this.state = EntityState.Running;
        } catch(Exception ex) {
            this.damage("resuming", ex);
            return;
        }

        try {
            this.debugMsg(DL_INFO, "resuming inboud signals");
            Signal s = !this._meta.inbound.empty() ? this._meta.inbound.front() : null;
            while(s !is null) {
                this.receive(s);
                this._meta.inbound.remove(s);
                s = !this._meta.inbound.empty() ? this._meta.inbound.front() : null;
            }
        } catch(Exception ex) {
            this.damage("resuming inboud signals", ex);
        }
    }

    protected void onSuspending() {
        try {
            this.debugMsg(DL_INFO, "suspending");

            this.meta.ticks.clear();
            
            while(!this._ticker.empty())
                Thread.sleep(WAITINGTIME);

            this.stop();
            
            this.suspendChildren();

            this.state = EntityState.Suspended;
        } catch(Exception ex) {
            this.damage("suspending", ex);
        }
    }

    protected void onDamaged() {
        this.debugMsg(DL_WARNING, "damaged");
            
        while(!this._ticker.empty())
            Thread.sleep(WAITINGTIME);

        try { /* cleanup and data rescue code here */ } catch {}

        this.debugMsg(DL_WARNING, "damaged but I didn't really do anything, not implemented yet");
    }

    protected void onDisposing() {
        try {
            this.debugMsg(DL_INFO, "disposing");
            this.disposeChildren();

            foreach(s; this.info.signals.dup())
                this.endListen(s);

            this.state = EntityState.Disposed;
        } catch(Exception ex) {
            this.damage("disposing", ex);
        }
    }

    private bool addChild(EntityMeta m) {
        auto e = this._flow.add(m);
        if(e !is null) {
            e._parent = this;
            this._children.put(e);
            return true;
        } else return false;
    }

    private void removeChild(Entity e) {
        this._flow.remove(e.info);
        this._children.remove(e);
    }

    private void createChildren() {
        foreach(EntityMeta m; this.meta.children.dup()) {
            this.addChild(m);
        }
    }

    private void disposeChildren() {
        foreach(e; this._children.dup()) {
            this.removeChild(e);
        } 
    }

    private void suspendChildren() {
        foreach(e; this._children.dup()) {
            if(e !is null)
                e.suspend();
        }
    }

    private void resumeChildren() {
        foreach(e; this._children.dup()) {
            if(e !is null)
                e.resume();
        }
    }
    
    private DataList!EntityMeta snapChildren() {
        auto l = new DataList!EntityMeta;
        foreach(e; this._children.dup()) {
            if(e !is null)
                l.put(e.snap());
        }
        return l;
    }
    
    protected void start() {}

    protected void stop() {}

    package void createTicker(Signal s, string tt) {
        auto ti = new TickInfo;
        ti.id = randomUUID;
        ti.entity = this.meta.info.ptr;
        ti.type = tt;
        ti.group = s.group;
        auto ticker = new Ticker(this, s, ti, (t){this._ticker.remove(t);});
        this._ticker.put(ticker);
        ticker.start();
    }

    package void createTicker(TickMeta tm) {
        auto ticker = new Ticker(this, tm, (t){this._ticker.remove(t);});
        this._ticker.put(ticker);
        ticker.start();
    }

    package bool receive(Signal s) {
        auto accepted = false;
        try {
            this.debugMsg(DL_INFO, "receiving");

            foreach(ms; this.info.signals)
                if(ms == s.type) {
                    if(this.state == EntityState.Running)
                        accepted = this.process(s);
                    else if(s.as!Anycast is null && (
                        this.state == EntityState.Suspending ||
                        this.state == EntityState.Suspended ||
                        this.state == EntityState.Resuming)) {
                        this.debugMsg(DL_DEBUG, "enqueuing signal");
                        /* anycasts cannot be received anymore,
                        all other signals are stored in meta */
                        this._entity.meta.inbound.put(s);
                        accepted = true;
                        break;
                    }
                }
        } catch(Exception ex) {
            this.debugMsg(DL_WARNING, "receiving", ex);
        }

        return accepted;
    }
    
    package bool process(Signal s) {
        auto accepted = false;
        try {
            this.debugMsg(DL_INFO, "processing");
            
            this.debugMsg(DL_DEBUG, "processing type listenings");
            foreach(tls; _typeListenings.keys) {
                if(tls == s.type) {
                    this.createTicker(s, _typeListenings[tls]);
                    accepted = true;
                }
            }

            this.debugMsg(DL_DEBUG, "processing ping listenings");
            if(this.as!IQuiet is null && (s.type == fqn!Ping || s.type == fqn!UPing)) {
                this.createTicker(s, fqn!SendPong);
                accepted = true;
            }

            this.debugMsg(DL_DEBUG, "processing dynamic listenings");
            foreach(l; this.meta.listenings) {
                if(l.signal == s.type) {
                    this.createTicker(s, l.tick);
                accepted = true;
                }
            }
        } catch(Exception ex) {
            this.debugMsg(DL_WARNING, "processing", ex);
        }
            
        return accepted;
    }

    private void _preventIdTheft(Signal s) {
        if(this._flow.config.preventIdTheft) {
            static if(is(T == Entity))
                s.source = this.obj.info.ptr;
            else
                s.source = null;
        }
    }
    
    package bool send(Unicast s, EntityPtr e) {
        if(this._flow.config.preventIdTheft) {
            static if(is(T == Entity))
                s.source = this.obj.info.ptr;
            else
                s.source = null;
        }

        return this._flow.send(s, e);
    }
    package bool send(Unicast s, EntityInfo e) { return this.send(s, e.ptr); }

    package bool send(Unicast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    package bool send(Multicast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    package bool send(Anycast s) {
        this._preventIdTheft(s);
        return this._flow.send(s);
    }
    
    package ListeningMeta listen(string s, string t) {
        this.ensureStateOr([EntityState.Initializing, EntityState.Running]);
        auto l = new ListeningMeta;
        l.signal = s;
        l.tick = t;

        auto found = false;
        foreach(ml; this.meta.listenings) {
            found = l.signal == ml.signal && l.tick == ml.tick;
            if(found) break;
        }

        if(!found)
        {
            this.meta.listenings.put(l);

            found = false;
            foreach(ms; this.info.signals) {
                found = ms == s;
                if(found) break;
            }

            if(!found)
                this.info.signals.put(s);
        }

        return l;
    }
    
    package void shut(ListeningMeta l) {
        this.ensureStateOr([EntityState.Disposing, EntityState.Running]);
        foreach(ms; this.info.signals.dup())
            if(ms == s) {
                this.info.signals.remove(s);

                foreach(ml; this.meta.listenings.dup())
                    if(ml == l) {
                        this.meta.listenings.remove(l);
                        break;
                    }

                break;
            }
        
    }

    package EntityMeta snap() {
        this.ensureState(EntityState.Suspended);

        auto m = this.meta.dup().as!EntityMeta;
        m.children.put(this.snapChildren());
        return m;
    }

    package bool spawn(EntityMeta m) {
        this.ensureState(EntityState.Running);

        return this.addChild(m);
    }
}