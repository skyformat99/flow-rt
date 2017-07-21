module __flow.util;

import std.traits;
import std.range;
import std.uuid;
import std.datetime;

/// Returns: full qualified name of type
template fqn(T) {
    enum fqn = fullyQualifiedName!T;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}

class InvalidStateException : Exception {this(){super(string.init);}}
class StateRefusedException : Exception {this(){super(string.init);}}

/// state machine mixin template
abstract class StateMachine(T) if (isScalarType!T) {
    import core.sync.rwmutex;

    private ReadWriteMutex _lock;
    private T _state;

    @property T state() {
        // no lock required since primitives are synced by D
        return this._state;
    }

    protected @property void state(T value) {
        auto allowed = false;
        T oldState;
        synchronized(this._lock.writer) {
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

        bool CheckState(TestState s) {
            try {
                this.ensureState(s);
                return true;
            } catch(InvalidStateException ex) {
                return false;
            }
        }

        bool CheckIllegalState(TestState s) {
            try {
                this.ensureState(s);
                return false;
            } catch(InvalidStateException ex) {
                return true;
            }
        }

        bool CheckSwitch(TestState s) {
            try {
                this.state = s;
                return true;
            } catch(StateRefusedException ex) {
                return false;
            }
        }

        bool CheckIllegalSwitch(TestState s) {
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
    auto t = new TestStateMachine;
    assert(t.state1Set, "initial state change wasn't executed");
    
    // t is now in state1
    assert(t.CheckIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.CheckIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.CheckState(TestState.State1), "couldn't check for valid state");

    assert(t.CheckIllegalSwitch(TestState.State1), "could switch state even its forbidden");
    assert(t.CheckIllegalSwitch(TestState.State3), "could switch state even its forbidden");

    // switching t to state2
    assert(t.CheckSwitch(TestState.State2), "could not switch state even it should be possible");
    assert(t.state2Set, "state change wasn't executed");

    assert(t.CheckIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.CheckIllegalState(TestState.State3), "illegal state check didn't cause expected exception");
    assert(t.CheckState(TestState.State2), "couldn't check for valid state");

    assert(t.CheckIllegalSwitch(TestState.State1), "could switch state even its forbidden");
    assert(t.CheckIllegalSwitch(TestState.State2), "could switch state even its forbidden");
    assert(t.CheckIllegalSwitch(TestState.State3), "could switch state even its requirement is not met");

    // switching to state3
    t.x = 5; assert(t.CheckSwitch(TestState.State3), "could not switch state even it should be possible"); 
    assert(t.state2Set, "state change wasn't executed");

    assert(t.CheckIllegalState(TestState.State1), "illegal state check didn't cause expected exception");
    assert(t.CheckIllegalState(TestState.State2), "illegal state check didn't cause expected exception");
    assert(t.CheckState(TestState.State3), "couldn't check for valid state");
}