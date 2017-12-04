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

    override void up() {
        import flow.util : as;

        synchronized(lock.writer)
            junctions[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));
    }

    override void down() {
        synchronized(lock.writer)
            junctions[this.id].remove(this.meta.info.space);
    }

    override bool ship(Unicast s) {
        import flow.util : as;

        synchronized(lock.reader)
            if(s.dst.space != this.meta.info.space && s.dst.space in junctions[this.id])
                if(this.meta.info.isConfirming) {
                    return junctions[this.id][s.dst.space].as!InProcessJunction.deliver(s.clone);
                } else {
                    junctions[this.id][s.dst.space].as!InProcessJunction.deliver(s.clone);
                    return true;
                }
        
        return false;
    }

    override bool ship(Anycast s) {
        import flow.util : as;

        // anycasts can only be send if its a confirming junction
        if(this.meta.info.isConfirming) {
            auto cw = containsWildcard(s.dst);

            synchronized(lock.reader)
                if(cw) {
                    foreach(j; junctions[this.id])
                        if(j.as!InProcessJunction.meta.info.space != this.meta.info.space
                        && j.as!InProcessJunction.meta.info.acceptsAnycast
                        && j.as!InProcessJunction.deliver(s))
                            return true;
                } else {
                    if(s.dst != this.meta.info.space
                    && s.dst in junctions[this.id]
                    && junctions[this.id][s.dst].as!InProcessJunction.meta.info.acceptsAnycast)
                        return junctions[this.id][s.dst].as!InProcessJunction.deliver(s.clone);
                }
        }
                    
        return false;
    }

    override bool ship(Multicast s) {
        import flow.util : as;

        auto cw = containsWildcard(s.dst);

        auto ret = false;
        synchronized(lock.reader)
            if(cw)
                foreach(j; junctions[this.id])
                    if(j.as!InProcessJunction.meta.info.space != this.meta.info.space
                    && j.as!InProcessJunction.meta.info.acceptsMulticast) {
                        if(this.meta.info.isConfirming) {
                            ret = j.as!InProcessJunction.deliver(s) || ret;
                        } else {
                            j.as!InProcessJunction.deliver(s);
                            ret = true;
                        }
                    }
            else
                if(s.dst != this.meta.info.space
                && s.dst in junctions[this.id]
                && junctions[this.id][s.dst].as!InProcessJunction.meta.info.acceptsMulticast)
                    if(this.meta.info.isConfirming) {
                        ret = junctions[this.id][s.dst].as!InProcessJunction.deliver(s.clone);
                    } else {
                        junctions[this.id][s.dst].as!InProcessJunction.deliver(s.clone);
                        ret = true;
                    }
                    
        return ret;
    }
}

private bool containsWildcard(string dst) {
    import std.algorithm.searching : any;

    return dst.any!(a => a = '*');
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.ipc.test;
    import flow.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.destroy;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", "flow.core.test.TestSendingContext");
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = "spc2.test.inproc.ipc.flow";
    ems.addEvent(EventType.OnTicking, "flow.core.test.UnicastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.AnycastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.MulticastSendingTestTick");
    sm1.addInProcJunction(junctionId);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", "flow.core.test.TestReceivingContext");
    emr.addReceptor("flow.core.test.TestUnicast", "flow.core.test.UnicastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestAnycast", "flow.core.test.AnycastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestMulticast", "flow.core.test.MulticastReceivingTestTick");
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

    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestUnicast, "didn't get test unicast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestAnycast, "didn't get test anycast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestMulticast, "didn't get test multicast");

    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestUnicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestAnycast, "didn't confirm test anycast");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestMulticast, "didn't confirm test multicast");
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.ipc.test;
    import flow.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.destroy;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", "flow.core.test.TestSendingContext");
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = "spc2.test.inproc.ipc.flow";
    ems.addEvent(EventType.OnTicking, "flow.core.test.UnicastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.AnycastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.MulticastSendingTestTick");
    sm1.addInProcJunction(junctionId, 0, false, true, true);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", "flow.core.test.TestReceivingContext");
    emr.addReceptor("flow.core.test.TestUnicast", "flow.core.test.UnicastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestAnycast", "flow.core.test.AnycastReceivingTestTick");
    sm2.addInProcJunction(junctionId, 0, false, true, true);

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

    // Since junctions isConfirming = false, anycast cannot work.
    // Multicast cannot be received since it has no receiver
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestUnicast, "didn't get test unicast");
    assert(!nsm2.entities[0].context.as!TestReceivingContext.gotTestAnycast, "got test anycast but shouldn't");
    assert(!nsm2.entities[0].context.as!TestReceivingContext.gotTestMulticast, "got test multicast but shouldn't");

    // Same for anycast. All other should get a confirmation which in this case tells it was send to destination space
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestUnicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.confirmedTestAnycast, "confirmed test anycast but shouldn't");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestMulticast, "didn't confirm test multicast");
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.ipc.test;
    import flow.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.destroy;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", "flow.core.test.TestSendingContext");
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = "spc2.test.inproc.ipc.flow";
    ems.addEvent(EventType.OnTicking, "flow.core.test.UnicastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.AnycastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.MulticastSendingTestTick");
    sm1.addInProcJunction(junctionId, 0, true, false, true);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", "flow.core.test.TestReceivingContext");
    emr.addReceptor("flow.core.test.TestUnicast", "flow.core.test.UnicastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestAnycast", "flow.core.test.AnycastReceivingTestTick");
    sm2.addInProcJunction(junctionId, 0, true, false, true);

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

    // Junction supports no anycast and multicast has no receiver
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestUnicast, "didn't get test unicast");
    assert(!nsm2.entities[0].context.as!TestReceivingContext.gotTestAnycast, "got test anycast but shouldn't");
    assert(!nsm2.entities[0].context.as!TestReceivingContext.gotTestMulticast, "got test multicast but shouldn't");

    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestUnicast, "didn't confirm test unicast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.confirmedTestAnycast, "confirmed test anycast but shouldn't");
    assert(!nsm1.entities[0].context.as!TestSendingContext.confirmedTestMulticast, "confirmed test multicast but shouldn't");
}

unittest {
    import core.thread;
    import flow.core;
    import flow.ipc.make;
    import flow.ipc.test;
    import flow.util;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.destroy;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto junctionId = randomUUID;

    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", "flow.core.test.TestSendingContext");
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = "spc2.test.inproc.ipc.flow";
    ems.addEvent(EventType.OnTicking, "flow.core.test.UnicastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.AnycastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.MulticastSendingTestTick");
    sm1.addInProcJunction(junctionId, 0, true, true, false);

    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", "flow.core.test.TestReceivingContext");
    emr.addReceptor("flow.core.test.TestUnicast", "flow.core.test.UnicastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestAnycast", "flow.core.test.AnycastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestMulticast", "flow.core.test.MulticastReceivingTestTick");
    sm2.addInProcJunction(junctionId, 0, true, true, false);

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

    // Junction supports no anycast and multicast has no receiver
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestUnicast, "didn't get test unicast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestAnycast, "didn't get test anycast");
    assert(!nsm2.entities[0].context.as!TestReceivingContext.gotTestMulticast, "got test multicast but shouldn't");

    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestUnicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestAnycast, "didn't confirm test anycast");
    assert(!nsm1.entities[0].context.as!TestSendingContext.confirmedTestMulticast, "confirmed test multicast but shouldn't");
}