# Introduction
You will learn how to initialize and use the basic components in a static environment.
For this you'll need to create a D executable which is linked against lib/libflow-core.so.

[SOURCECODE](src/introduction.d)

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
They are kind of memory of entities.
There is the config which is meant to store configuration data.
And there is the context meant to store runtime information.
However this separation is just pro forma.
While our first entity notes if it was successfully sending the casts,
our second one notes if it got them.
```D
class TestSendingConfig : Data {
    mixin data;

    mixin field!(string, "dstEntity");
    mixin field!(string, "dstSpace");
}

class TestSendingContext : Data {
    mixin data;

    mixin field!(bool, "unicast");
    mixin field!(bool, "anycast");
    mixin field!(bool, "multicast");
}

class TestReceivingContext : Data {
    mixin data;

    mixin field!(Unicast, "unicast");
    mixin field!(Anycast, "anycast");
    mixin field!(Multicast, "multicast");
}
```

## Ticks
Half of this ticks are defining the change of a "confirmed..." field on an entities information,
the other half are defining the change of a "got..." field on an entities information.
```D
class UnicastSendingTestTick : Tick {
    override void run() {
        auto cfg = this.config.as!TestSendingConfig;
        auto ctx = this.context.as!TestSendingContext;
        ctx.unicast = this.send(new TestUnicast, cfg.dstEntity, cfg.dstSpace);
    }
}

class AnycastSendingTestTick : Tick {
    override void run() {
        auto cfg = this.config.as!TestSendingConfig;
        auto ctx = this.context.as!TestSendingContext;
        ctx.anycast = this.send(new TestAnycast, cfg.dstSpace);
    }
}

class MulticastSendingTestTick : Tick {
    override void run() {
        auto cfg = this.config.as!TestSendingConfig;
        auto ctx = this.context.as!TestSendingContext;
        ctx.multicast = this.send(new TestMulticast, cfg.dstSpace);
    }
}

class UnicastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.unicast = this.trigger.as!Unicast;
    }
}

class AnycastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.anycast = this.trigger.as!Anycast;
    }
}

class MulticastReceivingTestTick : Tick {
    override void run() {
        auto c = this.context.as!TestReceivingContext;
        c.multicast = this.trigger.as!Multicast;
    }
}
```

## Main
This is the content of the main function.
First we create the systems order using helper functions, then kickstart it.
After everything happened we stop it and get out the information we then check for correctness.
This order generates just data which can and usually is serialized. It is the same data which falls out at the end.
That means if you got a system you can freeze it, snapshot it, end the process and restart everything again. It will continue where it got frozen.

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
    auto ems = sm1.addEntity("sending", fqn!TestSendingContext, fqn!TestSendingConfig);
    ems.config.as!TestSendingConfig.dstEntity = "receiving";
    ems.config.as!TestSendingConfig.dstSpace = spc2Domain;
    ems.addTick(fqn!UnicastSendingTestTick);
    ems.addTick(fqn!AnycastSendingTestTick);
    ems.addTick(fqn!MulticastSendingTestTick);
    sm1.addInProcJunction(junctionId);
    
    // we are creating metadata for our second space
    auto sm2 = createSpace(spc2Domain);
    auto emr = sm2.addEntity("receiving", fqn!TestReceivingContext);
    emr.addReceptor(fqn!TestUnicast, fqn!UnicastReceivingTestTick);
    emr.addReceptor(fqn!TestAnycast, fqn!AnycastReceivingTestTick);
    emr.addReceptor(fqn!TestMulticast, fqn!MulticastReceivingTestTick);
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
    Thread.sleep(100.msecs);

    // we cause the processes to stop ticking (freezing)
    spc2.freeze();
    spc1.freeze();

    // we picture/snapshot our spaces information
    auto nsm1 = spc1.snap();
    auto nsm2 = spc2.snap();

    // we check if all got the testsignal
    assert(nsm2.entities[0].context.as!TestReceivingContext.unicast !is null, "didn't get test unicast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.anycast !is null, "didn't get test anycast");
    assert(nsm2.entities[0].context.as!TestReceivingContext.multicast !is null, "didn't get test multicast");

    // we check if all got a confirmation for the testsignal
    assert(nsm1.entities[0].context.as!TestSendingContext.unicast, "didn't confirm test unicast");
    assert(nsm1.entities[0].context.as!TestSendingContext.anycast, "didn't confirm test anycast");
    assert(nsm1.entities[0].context.as!TestSendingContext.multicast, "didn't confirm test multicast");
```