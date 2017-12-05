module flow.ipc.inproc;

private import flow.data;
private import flow.core;

/// metadata of in process junction
class InProcessJunctionMeta : JunctionMeta {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "id");
}

/// junction allowing direct signalling between spaces hosted in same process
class InProcessJunction : Junction {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import std.uuid : UUID;

    private static __gshared ReadWriteMutex lock;
    private static shared InProcessJunction[string][UUID] junctions;

    /// instances with the same id belong to the same junction
    @property UUID id() {
        import flow.util : as;
        return this.meta.as!InProcessJunctionMeta.id;
    }

    shared static this() {
        lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    /// ctor
    this() {
        super();
    }

    override bool up() {
        import flow.util : as;

        synchronized(lock.writer)
            junctions[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));

        return true;
    }

    override bool down() {
        synchronized(lock.writer)
            if(this.id in junctions)
                junctions[this.id].remove(this.meta.info.space);

        return true;
    }

    override bool ship(Unicast s) {
        import flow.util : as;

        synchronized(lock.reader)
            if(s.dst.space in junctions[this.id]) {
                auto c = new InProcessChannel(this, junctions[this.id][s.dst.space]);
                return this.pack(s, c.recv.as!InProcessJunction.meta.info, c, (chan, pkg) => chan.transport(pkg)); // !interface to transport!
            }
        
        return false;
    }

    override bool ship(Anycast s) {
        import flow.util : as;
        
        if(s.dst != this.meta.info.space) synchronized(lock.reader)
            if(s.dst in junctions[this.id]) {
                auto c = new InProcessChannel(this, junctions[this.id][s.dst]);
                return this.pack(s, c.recv.as!InProcessJunction.meta.info, c, (chan, pkg) => chan.transport(pkg)); // !interface to transport!
            } else foreach(j; junctions[this.id]) {
                auto c = new InProcessChannel(this, j);
                return this.pack(s, c.recv.as!InProcessJunction.meta.info, c, (chan, pkg) => chan.transport(pkg)); // !interface to transport!
            }
                    
        return false;
    }

    override bool ship(Multicast s) {
        import flow.util : as;

        auto ret = false;
        if(s.dst != this.meta.info.space) synchronized(lock.reader)
            if(s.dst in junctions[this.id]) {
                auto c = new InProcessChannel(this, junctions[this.id][s.dst]);
                ret = this.pack(s, c.recv.as!InProcessJunction.meta.info, c, (chan, pkg) => chan.transport(pkg)) || ret; // !interface to transport!
            } else foreach(j; junctions[this.id]) {
                auto c = new InProcessChannel(this, j);
                ret = this.pack(s, c.recv.as!InProcessJunction.meta.info, c, (chan, pkg) => chan.transport(pkg)) || ret; // !interface to transport!
            }
                    
        return ret;
    }
}

class InProcessChannel : Channel {
    private InProcessJunction snd;
    private shared InProcessJunction recv;

    this(InProcessJunction snd, shared(InProcessJunction) recv) {
        this.snd = snd;
        this.recv = recv;
    }

    override bool transport(JunctionPacket p) {
        import flow.util : as;

        if(p.signal.as!Unicast !is null)
            return this.recv.as!InProcessJunction.deliver(p.signal.as!Unicast, p.auth);
        else if(p.signal.as!Anycast !is null)
            return this.recv.as!InProcessJunction.deliver(p.signal.as!Anycast, p.auth);
        else if(p.signal.as!Multicast !is null)
            return this.recv.as!InProcessJunction.deliver(p.signal.as!Multicast, p.auth);
        else return false;
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
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext);
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = spc2Domain;
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
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext);
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = spc2Domain;
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
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext);
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = spc2Domain;
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
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext);
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = spc2Domain;
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