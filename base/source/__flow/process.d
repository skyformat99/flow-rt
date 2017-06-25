module __flow.process;

import core.thread, core.sync.rwmutex, std.uuid;
import std.range.interfaces, std.string;

import __flow.exception, __flow.type, __flow.data, __flow.signal;
import __flow.entity;
import flow.base.dev, flow.base.interfaces, flow.base.data, flow.base.signals;


/// a hull hosting an entity
class Hull : StateMachine!EntityState { 
    

    this(, EntityMeta m) {
        
        

    }

    private void writeDebug(string msg, uint level) {
        debugMsg("hull("~this.address~");"~msg, level);
    }

    EntityMeta snap() {
        this.ensureState(EntityState.Suspended);

        auto m = this._entity.meta.clone.as!EntityMeta;
        m.children.put(this.snapChildren());
        return m;
    }

    bool spawn(EntityMeta m) {
        this.ensureState(EntityState.Running);

        return this.addChild(m);
    }

    EntityMeta kill(EntityInfo i) {
        this.ensureState(EntityState.Running);
        
        foreach(h; this._children)
            if(h.info == i) {
                h.suspend();
                auto m = h.snap();
                this.removeChild(h);
                return m;
            }
        
        return null;
    }
}

/// a flow process able to host the local swarm
class Flow
{
    private bool _shouldStop;
    private bool _isStopped;
    private ReadWriteMutex _lock;
    private Hull[string] _local;

    @property FlowPtr ptr() { return this.config.ptr; }

    private FlowConfig _config;
    @property FlowConfig config(){ return this._config; }

    this(FlowConfig c = null) {
        if(c is null) { // if no config is passed use defaults
            c = new FlowConfig;
            c.ptr = new FlowPtr;
            c.tracing = false;
            c.preventIdTheft = true;
        }

        this._lock = new ReadWriteMutex;
        this._config = c;
    }

    ~this() {
        this.stop();
    }

    DataList!EntityMeta stop() {
        auto m = new DataList!EntityMeta;
        if(!this._shouldStop) {
            this._shouldStop = true;

            this.writeDebug("{DESTROY}", 2);            

            synchronized(this._lock.writer) {
                auto hulls = new List!Hull;
                hulls.put(this._local.values);
                // eleminate non top hulls
                foreach(h; hulls.dup())
                    foreach(ph; hulls)
                        if(ph._children.contains(ph)) {
                            hulls.remove(ph);
                            break;
                        }

                // dispose top hulls
                foreach(h; hulls) {
                    m.put(this.remove(h.info));
                }
            }

            this._isStopped = true;
        }

        return m;
    }

    private void writeDebug(string msg, uint level) {
        debugMsg("process();"~msg, level);
    }

    Hull add(EntityMeta m) {
        synchronized(this._lock.writer) {
            return this.addInternal(m);
        }
    }

    private Hull addInternal(EntityMeta m) {
        Hull h;
        if(!this._shouldStop) {
            if(m is null)
                throw new ParameterException("entity meta can't be null");

            if(!Entity.canCreate(m.info.ptr.type))
                throw new UnsupportedObjectTypeException(m.info.ptr.type);
                
                try {
                    h = new Hull(this, m);//this._entity = Entity.create(type);
                    this.writeDebug("{ADD} entity("~h.info.ptr.type~"|"~h.address~")", 2);
                    this._local[h.address] = h;
                } catch(Exception exc) {
                    this.writeDebug("{ADD FAILED} entity("~m.info.ptr.type~"|"~m.info.ptr.id~"@"~m.info.ptr.domain~") ["~exc.msg~"]", 0);
                    if(h !is null && h.address in this._local)
                        this._local.remove(h.address);

                    return null;
                }
        }

        return h;
    }

    EntityMeta remove(EntityInfo i) {
        synchronized(this._lock.writer) {
            return this.removeInternal(i);
        }
    }

    private EntityMeta removeInternal(EntityInfo i) {
        EntityMeta m;
        if(!this._shouldStop) {
            string addr = i.ptr.id~"@"~i.ptr.domain;        
            if(addr in this._local) {    
                auto h = this._local[addr];
                this.writeDebug("{REMOVE} entity("~h.info.ptr.type~"|"~addr~")", 2);
                h.suspend();
                m = h.snap();
                h.dispose();
                this._local.remove(addr);
            }
        }
        return m;
    }

    Hull get(EntityInfo i) {
        if(!this._shouldStop)
            synchronized(this._lock.reader)
                return this._local[i.ptr.id~"@"~i.ptr.domain];
        
        return null;
    }

    void wait(bool delegate() expr) {
        if(!this._shouldStop) {
            while(!expr())
                Thread.sleep(WAITINGTIME);
        }
    }

    private void giveIdAndTypeIfHasnt(Signal s) {
        if(s.id == UUID.init)
            s.id = randomUUID;

        if(s.type is null || s.type == "")
            s.type = s.dataType;
    }

    bool send(Unicast s, EntityPtr e) {
        s.destination = e;
        return this.send(s);
    }

    bool send(Unicast s, EntityInfo e) {
        return this.send(s, e.ptr);
    }

    bool send(Unicast s) {
        if(!this._shouldStop) {
            auto d = s.destination;
            if(d !is null) {
                this.giveIdAndTypeIfHasnt(s);
                
                // sending only to acceptable
                foreach(r; this.getReceiver(s.type)) {
                    auto acceptable = r.ptr.id == d.id;
                    if(acceptable)
                        return this.deliver(s, r.ptr);
                }
            }
        }

        return false;
    }

    bool send(Multicast s) {
        if(!this._shouldStop) {
            this.giveIdAndTypeIfHasnt(s);
            
            auto found = false;
            // sending only to acceptable
            foreach(i; this.getReceiver(s.type)) {
                auto acceptable = i.ptr.domain.startsWith(s.domain);
                if(acceptable) {
                    this.deliver(s, i.ptr);
                    found = true;
                }
            }

            return found;
        }

        return false;
    }

    bool send(Anycast s) {
        if(!this._shouldStop) {
            this.giveIdAndTypeIfHasnt(s);
            
            auto delivered = false;
            // sending only to acceptable
            foreach(i; this.getReceiver(s.type)) {
                auto acceptable = i.ptr.domain.startsWith(s.domain);
                if(acceptable) {
                    delivered = this.deliver(s, i.ptr);
                    if(delivered) break;
                }
            }

            return delivered;
        }

        return false;
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

    private bool deliverInternal(Signal s, EntityPtr e) {
        if(!this._shouldStop) {
            if(e !is null)
                this.writeDebug("{SEND} signal("~s.type~", "~s.id.toString~") TO entity("~ e.id~"@"~e.domain~")", 3);

            bool isLocal;
            synchronized(this._lock.reader)
                isLocal = e is null || e.id~"@"~e.domain in this._local;
            if(isLocal)
                return this.receive(this.config.isolateMem ? s.clone.as!Signal : s, e);
            else{return false;/* TODO search online when implementing apache thrift*/}
        }

        return false;
    }

    bool receive(Signal s, EntityPtr e) {
        if(!this._shouldStop) {
            auto stype = s.type;
            auto addr = e.id~"@"~e.domain;
            this.writeDebug("{RECEIVE} signal("~s.type~") FOR entity("~addr~")", 3);

            Hull h;
            synchronized(this._lock.reader)
                if(addr in this._local)
                    h = this._local[addr];

            if(h !is null)
                return h.receive(s);
            else
                this.writeDebug("{RECEIVE} signal("~s.type~") entity NOT FOUND)", 3);
        }

        return false;
    }
    
    InputRange!EntityInfo getReceiver(string signal) {
        return this.getListener(signal).inputRangeObject;
        // TODO when using thrift call InputRange!EntityInfo getReceiver(FlowPtr process, string type) of others and merge results
    }

    EntityInfo[] getListener(string signal) {
        EntityInfo[] ret;
        if(!this._shouldStop) {
            this.writeDebug("{SEARCH} entities FOR signal("~signal~")", 4);

            synchronized(this._lock.reader) {
                foreach(id; this._local.keys) {
                    auto h = this._local[id];
                    auto i = h.info;
                    foreach(s; i.signals) {
                        if(s == signal) {
                            ret ~= i;
                            this.writeDebug("\t!!! entity("~i.ptr.type~"|"~h.address~")", 4);
                            break;
                        }
                    }
                    this.writeDebug("\t>>> entity("~i.ptr.type~"|"~h.address~")", 4);
                }
            }
        }

        return ret;
    }
}