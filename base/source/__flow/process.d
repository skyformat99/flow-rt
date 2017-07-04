module __flow.process;

import core.thread, core.sync.rwmutex, std.uuid;
import std.algorithm, std.range.interfaces, std.string;

import __flow.exception, __flow.type, __flow.data, __flow.signal, __flow.entity;
import flow.base.dev, flow.base.interfaces, flow.base.data, flow.base.signals;

enum FlowState {
    None = 0,
    Running,
    Disposing,
    Disposed,
    Died
}

/// a flow process able to host the local swarm
class Flow : StateMachine!FlowState {
    private Entity[string] _local;

    package FlowConfig config;

    this(FlowConfig c = null) {
        if(c is null) { // if no config is passed use defaults
            c = new FlowConfig;
            c.ptr = new FlowPtr;
            c.tracing = false;
            c.preventIdTheft = true;
        }

        this.config = c;

        this.state = FlowState.Running;
    }

    public void dispose() {
        this.state = FlowState.Disposing;
    }

    override protected bool onStateChanging(FlowState oldState, FlowState newState) {
        switch(newState) {
            case FlowState.Running:
                return oldState == FlowState.None;
            case FlowState.Disposing:
                return true;
            case FlowState.Disposed:
                return oldState == FlowState.Disposing;
            default:
                return false;
        }
    }

    override protected void onStateChanged(FlowState oldState, FlowState newState) {
        switch(newState) {
            case FlowState.Disposing:
                this.onDisposing(); break;
            default:
                break;
        }
    }

    private List!Entity GetTop() {
        auto top = new List!Entity;
        
        foreach(e; this._local.values)
            if(e.parent is null)
                top.put(e);

        return top;
    }

    private List!Entity GetRunningTop() {
        auto rtop = new List!Entity;
        
        foreach(e; this.GetTop())
            if(e.state == EntityState.Running)
                rtop.put(e);

        return rtop;
    }

    public void suspend() {
        synchronized(this.lock.reader) {
            auto rTop = this.GetRunningTop();
            
            foreach(e; rTop)
                e.suspend();
        }
    }

    public void resume() {
        synchronized(this.lock.reader) {
            auto top = this.GetTop();
            
            foreach(e; top)
                e.resume();
        }
    }

    public DataList!EntityMeta snap() {
        synchronized(this.lock.reader) {
            this.ensureState(FlowState.Running);
            auto m = new DataList!EntityMeta;
            auto top = this.GetTop();
            auto rTop = this.GetRunningTop();
            
            foreach(e; rTop)
                e.suspend();

            foreach(e; top)
                m.put(e.snap());
            
            foreach(e; rTop)
                e.resume();

            return m;
        }
    }

    protected void onDisposing() {
        try {
            this.suspend();
            Debug.msg(DL.FDebug, "waiting for disposing");
            synchronized(this.lock.writer) {
                Debug.msg(DL.Info, "disposing");
                foreach(e; this.GetTop())
                    this.removeInternal(e.meta.info);
            }

            this.state = FlowState.Disposed;
        } catch(Exception ex) {
            Debug.msg(DL.Fatal, ex, "disposing failed -> dying");

            this.state = FlowState.Died;
        }
    }

    public Entity add(EntityMeta m) {
        synchronized(this.lock.writer) {
            this.ensureState(FlowState.Running);
            Entity e = null;
            e = this.addInternal(m);
            e.resume();

            return e;
        }
    }

    package Entity addInternal(EntityMeta m) {
        Entity e = null;
        if(m is null)
            throw new ParameterException("entity meta can't be null");

        if(!Entity.canCreate(m.info.ptr.type))
            throw new UnsupportedObjectTypeException(m.info.ptr.type);
            
            string addr = m.info.ptr.id~"@"~m.info.ptr.domain;  
            try {
                Debug.msg(DL.Info, m.info, "adding entity");
                e = Entity.create(this, m);
                if(e !is null)
                    this._local[addr] = e;
                else Debug.msg(DL.Warning, "could not create entity");
            } catch(Exception ex) {
                Debug.msg(DL.Error, ex, "adding entity failed");
                if(e !is null && addr in this._local)
                    this._local.remove(addr);
            }

        return e;
    }

    public void remove(EntityInfo i) {
        synchronized(this.lock.writer) {
            this.ensureState(FlowState.Running);
            this.removeInternal(i);
        }
    }

    package void removeInternal(EntityInfo i) {
        auto addr = i.ptr.id~"@"~i.ptr.domain;        
        if(addr in this._local) try {
            Debug.msg(DL.Info, i, "removing entity");
            auto e = this._local[addr];

            if(e.state == EntityState.Running)
                throw new ParameterException("entity cannot be in a running state");

            if(e.state != EntityState.Disposed)
                e.dispose();
            this._local.remove(addr);
        } catch(Exception ex) {
            Debug.msg(DL.Error, ex, "removing entity failed -> killing");

            if(i !is null && addr in this._local)
                this._local.remove(addr);
        }
    }

    public Entity get(EntityInfo i) {
        synchronized(this.lock.reader) {
            this.ensureState(FlowState.Running);
            auto addr = i.ptr.id~"@"~i.ptr.domain;
            if(addr in this._local)
                return this._local[addr];
        }
        
        return null;
    }

    public void wait(bool delegate() expr) {
        while(!expr())
            Thread.sleep(WAITINGTIME);
    }

    private void giveIdAndTypeIfHasnt(Signal s) {
        if(s.id == UUID.init)
            s.id = randomUUID;

        if(s.type is null || s.type == string.init)
            s.type = s.dataType;
    }

    public bool send(Unicast s, EntityPtr e) {
        s.destination = e;
        return this.send(s);
    }

    public bool send(Unicast s, EntityInfo e) {
        return this.send(s, e.ptr);
    }

    public bool send(Unicast s) {
        Debug.msg(DL.FDebug, s, "sending unicast signal");
        try {
            this.ensureState(FlowState.Running);
            auto d = s.destination;
            if(d !is null) {
                this.giveIdAndTypeIfHasnt(s);
                
                // sending only to acceptable
                foreach(i; this.getReceiver(s.type)) {
                    auto saddr = s.source.id~"@"~s.source.domain;
                    auto raddr = i.ptr.id~"@"~i.ptr.domain;
                    if(saddr != raddr) {
                        auto acceptable = i.ptr.id == d.id;
                        if(acceptable) {
                            return this.deliver(s, i.ptr);
                        }
                    }
                }
            }
        } catch(Exception ex) {
            Debug.msg(DL.Info, ex, "sending unicast signal failed");
        }

        return false;
    }

    public bool send(Multicast s) {
        Debug.msg(DL.FDebug, s, "sending multicast signal");
        auto found = false;
        try {
            this.ensureState(FlowState.Running);
            this.giveIdAndTypeIfHasnt(s);
            
            // sending only to acceptable
            foreach(i; this.getReceiver(s.type)) {
                auto saddr = s.source.id~"@"~s.source.domain;
                auto raddr = i.ptr.id~"@"~i.ptr.domain;
                if(saddr != raddr) {
                    auto srcDomain = s.domain;
                    auto dstDomain = i.ptr.domain;
                    auto acceptable = dstDomain.startsWith(srcDomain);
                    if(acceptable) {
                        this.deliver(s, i.ptr);
                        found = true;
                    }
                }
            }
        } catch(Exception ex) {
            Debug.msg(DL.Info, ex, "sending multicast signal failed");
        }

        return found;
    }

    public bool send(Anycast s) {
        Debug.msg(DL.FDebug, s, "sending anycast signal");
        auto delivered = false;
        try {
            this.ensureState(FlowState.Running);
            this.giveIdAndTypeIfHasnt(s);
            
            // sending only to acceptable
            foreach(i; this.getReceiver(s.type)) {
                auto saddr = s.source.id~"@"~s.source.domain;
                auto raddr = i.ptr.id~"@"~i.ptr.domain;
                if(saddr != raddr) {
                    auto srcDomain = s.domain;
                    auto dstDomain = i.ptr.domain;
                    auto acceptable = dstDomain.startsWith(srcDomain);
                    if(acceptable) {
                        delivered = this.deliver(s, i.ptr);
                        if(delivered) break;
                    }
                }
            }
        } catch(Exception ex) {
            Debug.msg(DL.Info, ex, "sending anycast signal failed");
        }

        return delivered;
    }

    bool deliver(Unicast s, EntityPtr e) {
        return this.deliverInternal(s, e);
    }

    void deliver(Multicast s, EntityPtr e) {
        this.deliverInternal(s, e);
    }

    bool deliver(Anycast s, EntityPtr e) {
        return this.deliverInternal(s, e);
    }

    private bool deliverInternal(Signal s, EntityPtr p) {
        Debug.msg(DL.FDebug, "waiting for delivering signal");
        try {
            this.ensureState(FlowState.Running);
            Debug.msg(DL.FDebug, s, "delivering signal");
            auto addr = p.id~"@"~p.domain;
            if(addr in this._local) {
                auto e = this._local[addr];
                s = this.config.isolateMem ? s.dup().as!Signal : s;
                return e.receive(s);
            } else {
                Debug.msg(DL.FDebug, "delivering signal failed since entity is not present");
                return false;/* TODO search online when implementing junction*/
            }
        } catch(Exception ex) {
            Debug.msg(DL.Info, ex, "delivering signal failed");
        }

        return false;
    }
    
    private InputRange!EntityInfo getReceiver(string s) {
        return this.getListener(s).inputRangeObject;
        // TODO when using thrift call InputRange!EntityInfo getReceiver(FlowPtr process, string type) of others and merge results
    }

    private DataList!EntityInfo getListener(string s) {
        DataList!EntityInfo ret = new DataList!EntityInfo;
        
        Debug.msg(DL.FDebug, "waiting for searching destination of signal");
        synchronized(this.lock.reader) {
            Debug.msg(DL.FDebug, "searching destination of signal type "~s);
            foreach(id; this._local.keys) {
                auto e = this._local[id];
                auto i = e.meta.info;
                foreach(es; i.signals) {
                    if(es == s) {
                        ret.put(i);
                        Debug.msg(DL.FDebug, i, "found destination for signal");
                        break;
                    }
                }
            }
        }

        return ret;
    }
}