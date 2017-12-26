module flow.core.ipc.zeromq.mesh;

private import core.stdc.errno;
private import core.thread;
private import flow.core;
private import std.array;
private import std.string;
private import std.conv;
private import std.uuid;

extern(C)
{
    @nogc:
    void nn_err_abort();
    int nn_err_errno();
    const(char)* nn_err_strerror(int errnum);
}

/// at linking something bad is happening if "Data" symbol is not used in shared library
private static import flow.core.data.engine; private class __Foo : flow.core.data.engine.Data {mixin flow.core.data.engine.data;}

class MeshJunctionInfo : JunctionInfo {
    mixin data;

    mixin field!(string, "addr");
}

class MeshJunctionMeta : JunctionMeta {
    import flow.core.data;

    mixin data;

    mixin field!(string[], "known");
    mixin field!(long, "timeout");
}

private immutable IDLENGTH = 16;

private enum MsgCode : ubyte {
    Ping = 0,
    Info = 1,
    SignOff = 2,
    Verify = ubyte.max-3,
    Signal = ubyte.max-2,
    Accept = ubyte.max-1,
    Refuse = ubyte.max
}

private struct Msg {
    shared static size_t lastId;

    static size_t getNewId() {
        import core.atomic : atomicOp;
        return atomicOp!"+="(lastId, 1);
    }

    bool valid;
    Throwable error;
    MsgCode code;
    size_t id;
    ubyte[] src;
    ubyte[] data;

    this(MsgCode c, ubyte[] s, size_t i = getNewId, ubyte[] d = null) {
        code = c;
        src = s;
        id = i;
        data = d;
        valid = true;
    }

    this(ubyte[] pkg) {
        try {
            import std.range : popFront, popFrontN;
            code = pkg[0].as!MsgCode; pkg.popFront;
            src = pkg[0..IDLENGTH]; pkg.popFrontN(IDLENGTH);
            id = pkg[0..size_t.sizeof].unbin!size_t; pkg.popFrontN(size_t.sizeof);
            data = pkg;
            valid = true;
        } catch(Throwable thr) {
            this.error = thr;
        }
    }

    ubyte[] bin() {
        ubyte[] pkg = [this.code];
        pkg ~= src;
        pkg ~= id.bin;
        pkg ~= data;
        return pkg;
    }
}

private class MeshChannel : Channel {
    private import core.sync.mutex : Mutex;
    ubyte[] id;
    ubyte[] auth;

    Mutex aLock;
    bool[size_t] answers;
    bool[size_t] await;

    override @property MeshJunction own() {
        import flow.core.util : as;
        return super.own.as!MeshJunction;
    }
    
    override @property MeshJunctionInfo other()
    {return super.other.as!MeshJunctionInfo;}

    this(string dst, MeshJunction own, ubyte[] id, ubyte[] auth) {
        this.aLock = new Mutex;
        this.id = id;
        this.auth = auth;

        super(dst, own);
    }

    override protected void dispose() {
        while(this.await.length > 0)
            Thread.sleep(5.msecs);
    }

    override protected ubyte[] reqAuth() {
        debug Log.msg(LL.Debug, this.logPrefix~"peer requested auth");
        return this.auth;
    }
    
    override protected bool reqVerify(ref ubyte[] auth) {
        import std.conv : to;
        synchronized(this.own.lock.reader) if(this.own.state == JunctionState.Attached) {
            auto id = Msg.getNewId;
            debug Log.msg(LL.Debug, this.logPrefix~"request verification("~id.to!string~")");
            return this.send(Msg(
                MsgCode.Verify, this.own.sid, id,
                // auth bytes were already send at MsgCode.Info
                this.own.meta.info.space.bin));
        } else return false;
    }

    override protected bool transport(ref ubyte[] pkg) {
        import std.conv : to;
        synchronized(this.own.lock.reader) if(this.own.state == JunctionState.Attached) {
            auto id = Msg.getNewId;
            debug Log.msg(LL.Debug, this.logPrefix~"transport("~id.to!string~")");
            return this.send(Msg(
                MsgCode.Signal, this.own.sid, Msg.getNewId,
                this.own.meta.info.space.bin.pack~pkg));
        } else return false;
    }

    bool send(Msg msg) {
        import core.time : msecs;
        import std.datetime.systime : Clock;
        import std.conv : to;

        synchronized(this.aLock)
            this.await[msg.id] = true;
        scope(exit) this.await.remove(msg.id);
        if(!this.own.send(msg, this.id)) return false;

        auto time = Clock.currStdTime;
        auto timeout = this.own.meta.as!MeshJunctionMeta.timeout;
        while(msg.id !in this.answers && time + timeout.msecs.total!"hnsecs" > Clock.currStdTime)
            Thread.sleep(5.msecs);
        
        debug Log.msg(LL.Debug, this.logPrefix~"waited "~(Clock.currStdTime-time).to!string~" hnsecs for answer("~msg.id.to!string~")");

        synchronized(this.aLock)
            if(msg.id in this.answers) {
                scope(exit) this.answers.remove(msg.id);
                return this.answers[msg.id];
            } else return false;
    }
}

class MeshJunction : Junction {
    private import core.sync.mutex : Mutex;
    private import deimos.nanomsg.nn;
    private import deimos.nanomsg.pubsub;

    private int sock;
    private int sysSock;
    private int domainSock;
    private ubyte[] sid;

    private ReadWriteMutex cLock;
    private Mutex recvSysLock;
    private Mutex recvDomainLock;
    private bool _recvSys;
    private bool _recvDomain;
    private bool[Thread] _proc;
    private MeshChannel[string] channels;

    override @property MeshJunctionMeta meta() {
        import flow.core.util : as;
        return super.meta.as!MeshJunctionMeta;
    }

    override @property string[] list() {
        synchronized(this.cLock.reader)
            return this.channels.keys;
    }

    /// ctor
    this() {
        this.cLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.recvSysLock = new Mutex;
        this.recvDomainLock = new Mutex;
        super();
    }

    private void genId() {
        import std.uuid;
        this.sid = randomUUID.bin;
    }
    
    private void create() {
        this.sock = nn_socket(AF_SP, NN_PUB);
        if(this.sock < 0)
            throw new ChannelException ("creating publisher failed: "~nn_err_strerror (errno).to!string);

        this.sysSock = nn_socket(AF_SP, NN_SUB);
        if(this.sysSock < 0)
            throw new ChannelException ("creating system subscriber failed: "~nn_err_strerror (errno).to!string);

        this.domainSock = nn_socket(AF_SP, NN_SUB);
        if(this.domainSock < 0)
            throw new ChannelException ("creating domain subscriber failed: "~nn_err_strerror (errno).to!string);

        auto timeout = 50;
        ubyte[] sys = new ubyte[IDLENGTH];
        if(nn_setsockopt(this.sysSock, NN_SUB, NN_SUB_SUBSCRIBE, sys.ptr, sys.length) < 0)
            throw new ChannelException ("setting system subscriber failed: "~nn_err_strerror (errno).to!string);

        if(nn_setsockopt(this.sysSock, NN_SOL_SOCKET, NN_RCVTIMEO, &timeout, timeout.sizeof) < 0)
            throw new ChannelException ("setting system subscriber timeout failed: "~nn_err_strerror (errno).to!string);
        
        if(nn_setsockopt(this.domainSock, NN_SUB, NN_SUB_SUBSCRIBE, this.sid.ptr, this.sid.length) < 0)
            throw new ChannelException ("setting domain subscriber failed: "~nn_err_strerror (errno).to!string);

        if(nn_setsockopt(this.domainSock, NN_SOL_SOCKET, NN_RCVTIMEO, &timeout, timeout.sizeof) < 0)
            throw new ChannelException ("setting domain subscriber timeout failed: "~nn_err_strerror (errno).to!string);
    }

    private void bind() {
        auto rc = nn_bind(this.sock, this.meta.info.as!MeshJunctionInfo.addr.toStringz);
        if(rc < 0)
            throw new ChannelException ("binding failed: "~nn_err_strerror (errno).to!string);

        rc = nn_connect(this.sysSock, this.meta.info.as!MeshJunctionInfo.addr.toStringz);
        if(rc < 0)
            throw new ChannelException ("connecting system subscriber failed: "~nn_err_strerror (errno).to!string);

        rc = nn_connect(this.domainSock, this.meta.info.as!MeshJunctionInfo.addr.toStringz);
        if(rc < 0)
            throw new ChannelException ("connecting domain subscriber failed: "~nn_err_strerror (errno).to!string);
    }

    private bool connect(string addr) {
        import std.algorithm.searching : any;

        if(addr != this.meta.info.as!MeshJunctionInfo.addr) {
            Log.msg(LL.Message, this.logPrefix~"connects to "~addr);
            if(nn_connect(this.sock, addr.toStringz) < 0) {
                Log.msg(LL.Info, this.logPrefix~"connecting system subscriber failed: "~nn_err_strerror (errno).to!string);
                return false;
            }

            if(nn_connect(this.sysSock, addr.toStringz) < 0) {
                Log.msg(LL.Info, this.logPrefix~"connecting system subscriber failed: "~nn_err_strerror (errno).to!string);
                return false;
            }

            if(nn_connect(this.domainSock, addr.toStringz) < 0) {
                Log.msg(LL.Info, this.logPrefix~"connecting domain subscriber failed: "~nn_err_strerror (errno).to!string);
                return false;
            }
        }
        
        return true;
    }

    private void close(int sock) {
        int rc;
        while(rc != 0 && errno != EBADF && errno != EINVAL && errno != ETERM)
            rc = nn_close(sock);
        if(rc != 0)
            Log.msg(LL.Warning, this.logPrefix~"shutdown socket failed: "~nn_err_strerror (errno).to!string);
    }

    private void shutdown() {
        this.close(this.sock);
        this.close(this.sysSock);
        this.close(this.domainSock);
    }

    private void connect() {
        import std.parallelism : taskPool, task;
        import std.algorithm.mutation : remove;

        // connect to others
        size_t[] failed;
        foreach(i, k; this.meta.known)
            if(!this.connect(k))
                failed ~= i;
        
        // remove failed ones (they get added again as soon as they connect)
        foreach_reverse(f; failed)
            this.meta.known = this.meta.known.remove(f);

        // inform others of new node and send them own addr and auth info
        this.send(Msg(MsgCode.Info, this.sid, Msg.getNewId,
            this.meta.info.space.bin.pack
            ~this.meta.info.as!MeshJunctionInfo.addr.bin.pack
            ~this.auth));

        // ping
        this.send(Msg(MsgCode.Ping, this.sid, Msg.getNewId,
            this.meta.info.space.bin));
    }

    private void recvSys() {
        new Thread({
            while(this._recvSys)
                this.recv(this.sysSock);
        }).start();
    }

    private void recvDomain() {
        new Thread({
            while(this._recvDomain)
                this.recv(this.domainSock);
        }).start();
    }

    private void recv(int sock) {
        import std.parallelism : taskPool, task;

        void* buf;
        int rc = nn_recv (sock, &buf, NN_MSG, 0);

        if(rc >= 0) {
            scope(exit) nn_freemsg (buf);
            auto pkg = buf.as!(ubyte*)[IDLENGTH..rc].as!(ubyte[]);
                taskPool.put(task({
                    auto msg = Msg(pkg);
                    if(msg.valid) {
                        debug Log.msg(LL.Debug, this.logPrefix~"recv("~msg.id.to!string~", "~msg.code.to!string~")");
                        this.proc(msg);
                    } else
                        Log.msg(LL.Error, this.logPrefix~"deserializing msg failed", msg.error);
                }));
        } else if(errno != ETIMEDOUT)
            Log.msg(LL.Error, this.logPrefix~"recv failed: "~nn_err_strerror (errno).to!string);
    }

    private void proc(Msg msg) {
        import std.algorithm.searching : any;
        import std.conv : to;

        try {
            this._proc[Thread.getThis] = true;
            scope(exit) this._proc.remove(Thread.getThis);

            switch(msg.code) {
                case MsgCode.Ping: // if its a ping, send own junction info
                    synchronized(this.lock.reader) if(this.state == JunctionState.Attached) {
                        auto src = msg.data.unbin!string;
                        debug Log.msg(LL.Debug, this.logPrefix~"ping("~msg.id.to!string~") from "~src);
                        this.send(Msg(
                            MsgCode.Info, this.sid, msg.id,
                            this.meta.info.space.bin.pack
                            ~this.meta.info.as!MeshJunctionInfo.addr.bin.pack
                            ~this.auth
                        ), msg.src);
                    }
                    break;
                case MsgCode.Info:
                    synchronized(this.lock.reader) if(this.state == JunctionState.Attached) {
                        // if there is no channel to this junction, create one
                        auto src = msg.data.unpack.unbin!string;
                        auto addr = msg.data.unpack.unbin!string;

                        debug Log.msg(LL.Debug, this.logPrefix~"info("~msg.id.to!string~") from "~src);
                        // if not already in known connect to node and add to known if successful
                        if(!this.meta.known.any!((k)=>k==addr))
                            if(this.connect(addr))
                                this.meta.known ~= addr;

                        auto canReg = false;
                        synchronized(this.cLock.reader)
                            canReg = (src !in this.channels);
                        
                        if(canReg) {
                            this.register(new MeshChannel(
                                src, this, msg.src, msg.data
                            ));
                        }
                    }
                    break;
                case MsgCode.SignOff: // if a node signs off deregister its channel
                    auto src = msg.data.unbin!string;
                    debug Log.msg(LL.Debug, this.logPrefix~"signoff("~msg.id.to!string~") from "~src);

                    if(src in this.channels)
                        this.unregister(this.channels[src]);
                    break;
                case MsgCode.Verify:
                    synchronized(this.lock.reader) if(this.state == JunctionState.Attached) {
                        auto src = msg.data.unbin!string;

                        debug Log.msg(LL.Debug, this.logPrefix~"verify("~msg.id.to!string~") from "~src);
                        auto r = false; ubyte[] dst;
                        synchronized(this.cLock.reader)
                            if(src in this.channels) {
                                r = this.channels[src].verify(this.channels[src].auth);
                                dst = this.channels[src].id;
                            } else dst = msg.src;
                        
                        this.send(Msg(
                                r ? MsgCode.Accept : MsgCode.Refuse,
                                this.sid, msg.id, this.meta.info.space.bin), dst);
                    }
                    break;
                case MsgCode.Signal:
                    synchronized(this.lock.reader) if(this.state == JunctionState.Attached) {
                        auto src = msg.data.unpack.unbin!string;
                        debug Log.msg(LL.Debug, this.logPrefix~"signal("~msg.id.to!string~") from "~src);
                        
                        auto r = false; ubyte[] dst;
                        synchronized(this.cLock.reader) {
                            if(src in this.channels) {
                                debug Log.msg(LL.Debug, this.logPrefix~"channel found for answer("~msg.id.to!string~") to "~src);
                                r = this.channels[src].pull(msg.data);
                                dst = this.channels[src].id;
                            } else {
                                debug Log.msg(LL.Debug, this.logPrefix~"channel not found for answer("~msg.id.to!string~") to "~src);
                                dst = msg.src;
                            }
                        }

                        this.send(Msg(
                            r ? MsgCode.Accept : MsgCode.Refuse,
                            this.sid, msg.id, this.meta.info.space.bin), dst);
                    }
                    break;
                case MsgCode.Accept:
                case MsgCode.Refuse:
                    auto src = msg.data.unbin!string;

                    synchronized(this.cLock.reader) {
                        debug Log.msg(LL.Debug, this.logPrefix~"signal("~msg.id.to!string~") "~(msg.code == MsgCode.Accept ? "accepted" : "refused"));
                        if(src in this.channels)
                            synchronized(this.channels[src].aLock) if(msg.id in this.channels[src].await)
                                this.channels[src].answers[msg.id] = msg.code == MsgCode.Accept;
                    }
                    break;
                default:
                    Log.msg(LL.Error, this.logPrefix~"unknown message received");
                    break;
            }
        } catch(Throwable thr) {
            Log.msg(LL.Error, this.logPrefix~"processing message", thr);
        }
    }

    private bool send(Msg msg, ubyte[] dst = null) {
        if(dst is null)
            dst = new ubyte[IDLENGTH];

        auto pkg = dst~msg.bin;
        int rc = nn_send (this.sock, pkg.ptr, pkg.length, 0);

        if(rc < IDLENGTH+pkg.length) {
            debug Log.msg(LL.Debug, this.logPrefix~"sent("~msg.id.to!string~", "~msg.code.to!string~")");
            return true;
        } else {
            Log.msg(LL.Warning, this.logPrefix~"send("~msg.id.to!string~") failed: "~nn_err_strerror (errno).to!string);
            return false;
        }
    }

    /// registers a channel passing junction
    private void register(MeshChannel c) {
        import core.memory : GC;
        import core.time : msecs;
        import std.datetime.systime : Clock;

        synchronized(this.cLock.writer)            
            this.channels[c.dst] = c;
    }
    
    /// unregister a channel passing junction
    private void unregister(MeshChannel c) {
        import core.memory : GC;
        synchronized(this.cLock.writer)
            this.channels.remove(c.dst);
        c.dispose(); GC.free(&c);
    }

    override bool up() {
        try {
            this.genId();
            this.create();

            // start listening
            this._recvSys = true;
            this._recvDomain = true;
            this.recvSys();
            this.recvDomain();

            this.bind();
            this.connect();
            return true;
        } catch(Throwable thr) {
            Log.msg(LL.Error, this.logPrefix, thr);
            return false;
        }
    }

    override void down() {
        import core.memory : GC;

        // unregister channels
        synchronized(this.lock.reader)
            synchronized(this.cLock.writer)
                foreach(s, c; this.channels) {
                    this.channels.remove(c.dst);
                    c.dispose(); GC.free(&c);
                }
        
        synchronized(this.recvDomainLock)
            this._recvDomain = false;
        
        synchronized(this.recvSysLock)
            this._recvSys = false;

        // wait for processings to end
        while(this._proc.length > 0)
            Thread.sleep(5.msecs);

        // sign off first
        this.send(Msg(
            MsgCode.SignOff, this.sid, Msg.getNewId,
            this.meta.info.space.bin));
        
        this.shutdown();
    }

    override Channel get(string dst) {
        synchronized(this.lock.reader)
            synchronized(this.cLock.reader)
                if(dst in this.channels)
                    return this.channels[dst];
        
        return null;
    }
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    long timeout = 5000,
    ushort level = 0
) {
    return sm.addMeshJunction(id, addr, known, timeout, level, false, false, false);
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    long timeout,
    ushort level,
    bool hiding,
    bool indifferent,
    bool introvert
) {
    import flow.core.util : as;
    
    auto jm = sm.addJunction(
        id,
        fqn!MeshJunctionMeta,
        fqn!MeshJunctionInfo,
        fqn!MeshJunction,
        level,
        hiding,
        indifferent,
        introvert
    );
    jm.info.as!MeshJunctionInfo.addr = addr;
    jm.as!MeshJunctionMeta.known = known;
    jm.as!MeshJunctionMeta.timeout = timeout;

    return jm;
}

/// creates metadata for an in process junction 
JunctionMeta createMeshJunction(
    SpaceMeta sm,
    UUID id,
    string addr,
    string[] known,
    long timeout = 5000,
    ushort level = 0,
    bool hiding = false,
    bool indifferent = false,
    bool introvert = false
) {
    import flow.core.util : as;
    
    auto jm = createJunction(
        id,
        fqn!MeshJunctionMeta,
        fqn!MeshJunctionInfo,
        fqn!MeshJunction,
        level,
        hiding,
        indifferent,
        introvert
    );
    jm.info.as!MeshJunctionInfo.addr = addr;
    jm.as!MeshJunctionMeta.known = known;
    jm.as!MeshJunctionMeta.timeout = timeout;

    return jm;
}

unittest { test.header("ipc.nanomsg.mesh: fully enabled passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit)
        proc.dispose();

    Log.logLevel = LL.Debug;

    auto spc1Domain = "spc1.test.inproc.gears.core.flow";
    auto spc2Domain = "spc2.test.inproc.gears.core.flow";

    auto junctionId1 = randomUUID;
    auto junctionId2 = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending");
    auto a = new TestSendingAspect; ems.aspects ~= a;
    a.wait = 20;
    a.dstEntity = "receiving";
    a.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addMeshJunction(junctionId1, "inproc://j1", ["inproc://j2"], 10);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving");
    emr.aspects ~= new TestReceivingAspect;
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    sm2.addMeshJunction(junctionId2, "inproc://j2", ["inproc://j1"], 10);
    
    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(100.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.unicast !is null, "didn't get test unicast");
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.anycast !is null, "didn't get test anycast");
    assert(nsm2.entities[0].aspects[0].as!TestReceivingAspect.multicast !is null, "didn't get test multicast");

    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.unicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.anycast, "didn't confirm test anycast");
    assert(nsm1.entities[0].aspects[0].as!TestSendingAspect.multicast, "didn't confirm test multicast");
test.footer(); }