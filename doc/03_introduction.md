# Introduction
You will learn how to initialize and use the basic components in a static environment.
For this you'll need to create a D executable which is linked against lib/libflow-core.so.

## Neccessary imports
```D
import flow.core;   // core functionality of flow
import flow.data;   // everything concerning data objects
import flow.util;   // a few little helpers
```

## Signals
They do not contain any custom data for this scenario.
There is one testsignal for each signal type.
```D
class TestUnicast : Unicast {
    mixin data;
}

class TestAnycast : Anycast {
    mixin data;
}

class TestMulticast : Multicast {
    mixin data;
}
```

## Data of entities
They are kind of the memory of entities
While our first entity notes if it was successfully sending the casts, our second one notes if it got them.
```D
class TestSendingContext : Data {
    mixin data;

    mixin field!(string, "dstEntity");
    mixin field!(string, "dstSpace");
    mixin field!(bool, "confirmedTestUnicast");
    mixin field!(bool, "confirmedTestAnycast");
    mixin field!(bool, "confirmedTestMulticast");
}

class TestReceivingContext : Data {
    mixin data;

    mixin field!(bool, "gotTestUnicast");
    mixin field!(bool, "gotTestAnycast");
    mixin field!(bool, "gotTestMulticast");
}
```

## Ticks
Half of this ticks are defining the change of a "confirmed..." field on an entities information,
the other half are defining the change of a "got..." field on an entities information.
```D
class UnicastSendingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestSendingContext;
        c.confirmedTestUnicast = this.send(new TestUnicast, c.dstEntity, c.dstSpace);
    }
}

class AnycastSendingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestSendingContext;
        c.confirmedTestAnycast = this.send(new TestAnycast, c.dstSpace);
    }
}

class MulticastSendingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestSendingContext;
        c.confirmedTestMulticast = this.send(new TestMulticast, c.dstSpace);
    }
}

class UnicastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.gotTestUnicast = true;
    }
}

class AnycastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.gotTestAnycast = true;
    }
}

class MulticastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.gotTestMulticast = true;
    }
}
```

## Main
This is the content of the main function.
First we create the systems order using helper functions, then kickstart it.
After everything happened we stop it and get out the information we then check for correctness.

```D
    // we want to bind two spaces together by an inprocess junction
    import core.thread;
    import core.time;
    import flow.ipc;
    import std.uuid;

    // we create a process which hosts our spaces
    auto proc = new Process;
    // the process should be destroyed when on exiting the scope
    scope(exit) proc.destroy;

    // we define domains for our spaces
    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    // we define a junction spaces can use to communicate
    auto junctionId = randomUUID;

    // we are creating metadata for our first space
    auto sm1 = createSpace(spc1Domain);
    auto ems = sm1.addEntity("sending", "flow.core.test.TestSendingContext");
    ems.context.as!TestSendingContext.dstEntity = "receiving";
    ems.context.as!TestSendingContext.dstSpace = "spc2.test.inproc.ipc.flow";
    ems.addEvent(EventType.OnTicking, "flow.core.test.UnicastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.AnycastSendingTestTick");
    ems.addEvent(EventType.OnTicking, "flow.core.test.MulticastSendingTestTick");
    sm1.addInProcJunction(junctionId);
    
    // we are creating metadata for our second space
    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", "flow.core.test.TestReceivingContext");
    emr.addReceptor("flow.core.test.TestUnicast", "flow.core.test.UnicastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestAnycast", "flow.core.test.AnycastReceivingTestTick");
    emr.addReceptor("flow.core.test.TestMulticast", "flow.core.test.MulticastReceivingTestTick");
    sm2.addInProcJunction(junctionId);

    // we add created spaces to our process and get back the instances
    auto spc1 = proc.add(sm1);
    auto spc2 = proc.add(sm2);

    // we let the spaces start processing (ticking)
    // 2 before 1 since 2 must be up when 1 begins
    spc2.tick();
    spc1.tick();

    // lets give it a few miliseconds
    // (usually stop when someone is shutting down your app and not when something happened)
    Thread.sleep(100.msecs)

    // we cause the processes to stop ticking (freezing)
    spc2.freeze();
    spc1.freeze();

    // we picture/snapshot our spaces information
    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // we check if all got the testsignal
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestUnicast, "didn't get test unicast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestAnycast, "didn't get test anycast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.gotTestMulticast, "didn't get test multicast");

    // we check if all got a confirmation for the testsignal
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestUnicast, "didn't confirmed test unicast");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestAnycast, "didn't confirmed test anycast");
    assert(nsm1.entities[0].context.as!TestSendingContext.confirmedTestMulticast, "didn't confirmed test multicast");
```