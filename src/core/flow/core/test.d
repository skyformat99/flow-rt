module flow.core.test;

/// imports for tests
version(unittest) {
    private import flow.core.data;
    private import flow.core.engine;
    private import flow.data;
    private import flow.util;
}

/// casts for testing
version(unittest) {
    class TestUnicast : Unicast {
        mixin data;
    }

    class TestAnycast : Anycast {
        mixin data;
    }
    class TestMulticast : Multicast {
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