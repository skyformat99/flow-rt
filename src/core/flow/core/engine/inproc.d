module flow.core.engine.inproc;

private import flow.core.data;
private import flow.core.engine.data;
private import flow.core.engine.engine;
private import flow.core.util;
private import std.uuid;

/// metadata of in process junction
class InProcessJunctionMeta : JunctionMeta {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "id");
}

class InProcessChannel : Channel {
    private bool master;
    private InProcessChannel peer;

    override @property InProcessJunction own() {
        import flow.core.util : as;
        return super.own.as!InProcessJunction;
    }

    this(InProcessJunction own, InProcessJunction recv, InProcessChannel peer = null) {
        if(peer is null) {
            this.master = true;
            this.peer = new InProcessChannel(recv, own, this);
        } else
            this.peer = peer;
        
        super(recv.meta.info.space, own);
        
        own.register(this);
    }

    override protected void dispose() {
        import core.memory : GC;
        if(this.master) {
            this.peer.dispose; GC.free(&this.peer);
        }

        this.own.unregister(this);

        super.dispose;
    }

    override protected ubyte[] reqAuth() {
        return this.peer.getAuth();
    }
    
    override protected bool reqVerify(ref ubyte[] auth) {
        return this.peer.verify(auth);
    }

    override protected bool transport(ref ubyte[] pkg) {
        import flow.core.util : as;

        return this.peer.pull(pkg, this.own.meta.info);
    }
}

/// junction allowing direct signalling between spaces hosted in same process
class InProcessJunction : Junction {
    private import std.uuid : UUID;

    private static __gshared ReadWriteMutex pLock;
    private static shared InProcessJunction[string][UUID] pool;

    private ReadWriteMutex cLock;
    private InProcessChannel[string] channels;

    override @property InProcessJunctionMeta meta() {
        import flow.core.util : as;
        return super.meta.as!InProcessJunctionMeta;
    }

    /// instances with the same id belong to the same junction
    @property UUID id() {return this.meta.id;}

    override @property string[] list() {
        synchronized(this.lock.reader)
            return pool[this.id].keys;
    }

    shared static this() {
        pLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    /// ctor
    this() {
        this.cLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        super();
    }

    /// registers a channel passing junction
    private void register(InProcessChannel c) {
        synchronized(pLock.reader)
            if(this.id in pool) // if is up
                this.channels[c.dst] = c;
    }
    
    /// unregister a channel passing junction
    private void unregister(InProcessChannel c) {
        if(this.id in pool) // if is up
            this.channels.remove(c.dst);
    }

    override bool up() {
        import flow.core.util : as;

        synchronized(pLock)
            if(this.id !in pool) // if is down
                synchronized(this.cLock)
                    pool[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));

        return true;
    }

    override void down() {
        import core.memory : GC;
        synchronized(pLock) {
            synchronized(this.cLock)
                foreach(dst, c; this.channels)
                    if(c.master) {c.dispose(); GC.free(&c);}

            if(this.id in pool)
                pool[this.id].remove(this.meta.info.space);
        }
    }

    override Channel get(string dst) {
        import flow.core.util : as;

        synchronized(pLock.reader)
            synchronized(this.lock.reader)
                synchronized(this.cLock.reader) {
                    if(dst in pool[this.id]) {
                        if(dst in this.channels)
                            return this.channels[dst];
                        else {
                            auto recv = pool[this.id][dst];
                            auto chan = new InProcessChannel(this.as!InProcessJunction, recv.as!InProcessJunction);
                            return chan.handshake() ? chan : null;
                        }
                    }
                }

        return null;
    }
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0
) {
    return sm.addInProcJunction(id, level, false, false, false);
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level,
    bool anonymous,
    bool indifferent,
    bool introvert
) {
    import flow.core.engine.inproc : InProcessJunctionMeta;
    import flow.core.util : as;
    
    auto jm = sm.addJunction(
        "flow.core.engine.inproc.InProcessJunctionMeta",
        "flow.core.engine.inproc.InProcessJunction",
        level,
        anonymous,
        indifferent,
        introvert
    ).as!InProcessJunctionMeta;
    jm.id = id;

    return jm;
}

unittest { test.header("TEST engine.inproc: fully enabled passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext, fqn!TestSendingConfig);
    ems.config.as!TestSendingConfig.dstEntity = "receiving";
    ems.config.as!TestSendingConfig.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", fqn!TestReceivingContext);
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    sm2.addInProcJunction(junctionId);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(5.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    assert(nsm2.entities[0].context.as!TestReceivingContext.unicast !is null, "didn't get test unicast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.anycast !is null, "didn't get test anycast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.multicast !is null, "didn't get test multicast");

    assert(nsm1.entities[0].context.as!TestSendingContext.unicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].context.as!TestSendingContext.anycast, "didn't confirm test anycast");
    assert(nsm1.entities[0].context.as!TestSendingContext.multicast, "didn't confirm test multicast");
test.footer(); }

unittest { test.header("TEST engine.inproc: anonymous (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext, fqn!TestSendingConfig);
    ems.config.as!TestSendingConfig.dstEntity = "receiving";
    ems.config.as!TestSendingConfig.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, true, false, false);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", fqn!TestReceivingContext);
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, true, false, false);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(5.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions anonymous = true, anycast cannot work.
    // Multicast cannot be received since it has no receiver but should be confirmed
    assert(nsm2.entities[0].context.as!TestReceivingContext.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.multicast !is null), "got test multicast but shouldn't");

    // Same for anycast. All other should get a confirmation which in this case tells it was send to destination space
    assert(nsm1.entities[0].context.as!TestSendingContext.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.anycast, "confirmed test anycast but shouldn't");
    assert(nsm1.entities[0].context.as!TestSendingContext.multicast, "didn't confirm test multicast");
test.footer(); }

unittest { test.header("TEST engine.inproc: indifferent (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext, fqn!TestSendingConfig);
    ems.config.as!TestSendingConfig.dstEntity = "receiving";
    ems.config.as!TestSendingConfig.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, false, true, false);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", fqn!TestReceivingContext);
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, false, true, false);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(5.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions indifferent = true, anycast cannot work.
    // Multicast cannot be received since it has no receiver but should be confirmed
    assert(nsm2.entities[0].context.as!TestReceivingContext.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.multicast !is null), "got test multicast but shouldn't");

    assert(nsm1.entities[0].context.as!TestSendingContext.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.anycast, "confirmed test anycast but shouldn't");
    assert(nsm1.entities[0].context.as!TestSendingContext.multicast, "didn't confirm test multicast");
test.footer(); }

unittest { test.header("TEST engine.inproc: !acceptsMulticast (not) passing of signals");
    import core.thread;
    import flow.core.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.dispose;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext, fqn!TestSendingConfig);
    ems.config.as!TestSendingConfig.dstEntity = "receiving";
    ems.config.as!TestSendingConfig.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId, 0, false, false, true);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", fqn!TestReceivingContext);
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
    sm2.addInProcJunction(junctionId, 0, false, false, true);

    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    Thread.sleep(5.msecs);Thread.sleep(5.msecs);

    spc2.freeze();
    spc1.freeze();

    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // Since junctions indifferent = true, it is not accepting anything but the directed unicasts.
    assert(nsm2.entities[0].context.as!TestReceivingContext.unicast !is null, "didn't get test unicast");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.anycast !is null), "got test anycast but shouldn't");
    assert(!(nsm2.entities[0].context.as!TestReceivingContext.multicast !is null), "got test multicast but shouldn't");

    assert(nsm1.entities[0].context.as!TestSendingContext.unicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.anycast, "confirmed test anycast but shouldn't");
    assert(!nsm1.entities[0].context.as!TestSendingContext.multicast, "confirmed test multicast but shouldn't");
test.footer(); }