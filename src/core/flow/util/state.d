module flow.util.state;

private static import flow.util.error;
private static import std.traits;

/// thrown when state machine detects an invalid state for operation
class InvalidStateException : flow.util.error.FlowException {mixin flow.util.error.exception;}

/// thrown when state machine refuses switch to given state
class StateRefusedException : flow.util.error.FlowException {mixin flow.util.error.exception;}

/// state machine mixin template
abstract class StateMachine(T) if (std.traits.isScalarType!T) {
    private import core.sync.rwmutex : ReadWriteMutex;

    private ReadWriteMutex _lock;
    protected @property ReadWriteMutex lock(){return this._lock;}
    private T _state;

    /// actual state
    @property T state() {
        // no lock required since primitives are synced by D
        return this._state;
    }

    protected @property void state(T value) {
        auto allowed = false;
        T oldState;
        synchronized(this.lock.writer) {
            if(this._state != value) {
                allowed = this.onStateChanging(this._state, value);

                if(allowed) {
                    oldState = this._state;
                    this._state = value;
                }
            }
        }
        
        if(allowed)
            this.onStateChanged(oldState, this._state);
        else throw new StateRefusedException;
    }

    protected this() {
        this._lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        this.onStateChanged(this.state, this.state);
    }

    protected void ensureState(T requiredState) {
        // no lock required since primitives are synced by D
        if(this._state != requiredState)
            throw new InvalidStateException();
    }

    // TODO replace ensure state or overloadings with template
    protected void ensureStateOr(T state1, T state2) {
        auto state = this._state;
        if(state != state1 && state != state2)
            throw new InvalidStateException();
    }

    protected void ensureStateOr(T state1, T state2, T state3) {
        auto state = this._state;
        if(state != state1 && state != state2 && state != state3)
            throw new InvalidStateException();
    }

    protected void ensureStateOr(T state1, T state2, T state3, T state4) {
        auto state = this._state;
        if(state != state1 && state != state2 && state != state3 && state != state4)
            throw new InvalidStateException();
    }

    protected bool onStateChanging(T oldState, T newState) {return true;}
    protected void onStateChanged(T oldState, T newState) {}
}

version(unittest) {
    enum TestState {
        State1,
        State2,
        State3
    }

    class TestStateMachine : StateMachine!TestState {
        int x;
        bool state1Set, state2Set, state3Set;

        override protected bool onStateChanging(TestState oldState, TestState newState) {
            switch(newState) {
                case TestState.State2:
                    return oldState == TestState.State1;
                case TestState.State3:
                    return canSwitchToState3();
                default: return false;
            }
        }

        override protected void onStateChanged(TestState oldState, TestState newState) {
            switch(newState) {
                case TestState.State1:
                    this.onState1();
                    break;
                case TestState.State2:
                    this.onState2();
                    break;
                case TestState.State3:
                    this.onState3();
                    break;
                default: break;
            }
        }

        void onState1() {
            this.state1Set = true;
        }

        void onState2() {
            this.state2Set = true;
        }

        void onState3() {
            this.state3Set = true;
        }

        bool canSwitchToState3() {
            return x > 4;
        }

        bool checkState(TestState s) {
            try {
                this.ensureState(s);
                return true;
            } catch(InvalidStateException ex) {
                return false;
            }
        }

        bool checkIllegalState(TestState s) {
            try {
                this.ensureState(s);
                return false;
            } catch(InvalidStateException ex) {
                return true;
            }
        }

        bool checkSwitch(TestState s) {
            try {
                this.state = s;
                return true;
            } catch(StateRefusedException ex) {
                return false;
            }
        }

        bool checkIllegalSwitch(TestState s) {
            try {
                this.state = s;
                return false;
            } catch(StateRefusedException ex) {
                return true;
            }
        }
    }
}

unittest {
    import std.stdio : writeln;
    writeln("testing state machine");

    auto t = new TestStateMachine;
    assert(t.state1Set, "initial state change wasn't executed");
    
    // t is now in state1
    assert(t.checkIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State1), "couldn't check for valid state");

    assert(t.checkIllegalSwitch(TestState.State1), "could switch state even its forbidden");
    assert(t.checkIllegalSwitch(TestState.State3), "could switch state even its forbidden");

    // switching t to state2
    assert(t.checkSwitch(TestState.State2), "could not switch state even it should be possible");
    assert(t.state2Set, "state change wasn't executed");

    assert(t.checkIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State2), "couldn't check for valid state");

    assert(t.checkIllegalSwitch(TestState.State1), "could switch state even its forbidden");
    assert(t.checkIllegalSwitch(TestState.State2), "could switch state even its forbidden");
    assert(t.checkIllegalSwitch(TestState.State3), "could switch state even its requirement is not met");

    // switching to state3
    t.x = 5; assert(t.checkSwitch(TestState.State3), "could not switch state even it should be possible"); 
    assert(t.state2Set, "state change wasn't executed");

    assert(t.checkIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.checkIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.checkState(TestState.State3), "couldn't check for valid state");
}