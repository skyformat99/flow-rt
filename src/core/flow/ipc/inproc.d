module flow.ipc.inproc;

private import flow.data;
private import flow.core;

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
        import flow.util : as;
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
        if(this.master)
            this.peer.destroy;

        this.own.unregister(this);
    }

    override protected ubyte[] getAuth() {
        return this.peer.auth;
    }
    
    override protected bool reqAuthentication(ubyte[] auth) {
        return this.peer.authenticate(auth);
    }

    override protected bool transport(ubyte[] pkg) {
        import flow.util : as;

        return this.peer.pull(pkg, this.own.meta.info);
    }
}

/// junction allowing direct signalling between spaces hosted in same process
class InProcessJunction : Junction {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import std.uuid : UUID;

    private static __gshared ReadWriteMutex pLock;
    private static shared InProcessJunction[string][UUID] pool;

    private ReadWriteMutex cLock;
    private InProcessChannel[string] channels;

    override @property InProcessJunctionMeta meta() {
        import flow.util : as;
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
        import flow.util : as;

        synchronized(pLock.writer)
            if(this.id !in pool) // if is down
                synchronized(this.cLock.writer)
                    pool[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));

        return true;
    }

    override void down() {
        synchronized(pLock.writer) {
            synchronized(this.cLock.writer)
                foreach(dst, c; this.channels)
                    synchronized(c.writer)
                        c.dispose();

            if(this.id in pool)
                pool[this.id].remove(this.meta.info.space);
        }
    }

    override Channel get(string dst) {
        import flow.util : as;

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

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.util;
    import std.stdio;
    import std.uuid;

    writeln("TEST inproc: fully enabled passing of signals");

    auto proc = new Process;
    scope(exit) proc.destroy;

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

    Thread.sleep(100.msecs);

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
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.util;
    import std.stdio;
    import std.uuid;

    writeln("TEST inproc: anonymous (not) passing of signals");

    auto proc = new Process;
    scope(exit) proc.destroy;

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

    Thread.sleep(100.msecs);

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
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.util;
    import std.stdio;
    import std.uuid;

    writeln("TEST inproc: indifferent (not) passing of signals");

    auto proc = new Process;
    scope(exit) proc.destroy;

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

    Thread.sleep(100.msecs);

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
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.util;
    import std.stdio;
    import std.uuid;

    writeln("TEST inproc: !acceptsMulticast (not) passing of signals");

    auto proc = new Process;
    scope(exit) proc.destroy;

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

    Thread.sleep(100.msecs);

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
}