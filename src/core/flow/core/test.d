module flow.core.test;

/// imports for tests
version(unittest) {
    import flow.core;
    import flow.data;
    import flow.util;
}

/// casts for testing
version(unittest) {
    class TestUnicast : flow.core.data.Unicast {
        mixin data;
    }

    class TestAnycast : flow.core.data.Anycast {
        mixin data;
    }
    class TestMulticast : flow.core.data.Multicast {
        mixin data;
    }
}

/// default test blocks
version(unittest) {
    class TestSendingContext : Data {
        mixin data;

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

    class UnicastSendingTestTick : Tick {
        override void run() {
            auto c = this.context.as!TestSendingContext;
            c.confirmedTestUnicast = true;
        }
    }

    class AnycastSendingTestTick : Tick {
        override void run() {
            auto c = this.context.as!TestSendingContext;
            c.confirmedTestAnycast = true;
        }
    }

    class MulticastSendingTestTick : Tick {
        override void run() {
            auto c = this.context.as!TestSendingContext;
            c.confirmedTestMulticast = true;
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
}

/// helper functions
version(unittest) {
    SpaceMeta createSpace(string id, size_t worker = 1) {
        auto sm = createData("flow.core.data.SpaceMeta").as!SpaceMeta;
        sm.id = id;
        sm.worker = worker;

        return sm;
    }

    EntityMeta addEntity(SpaceMeta sm) {
        auto em = createData("flow.core.data.EntityMeta").as!EntityMeta;
        em.ptr = createData("flow.core.data.EntityMeta").as!EntityPtr;

        sm.entities ~= em;
        return em;
    }
}