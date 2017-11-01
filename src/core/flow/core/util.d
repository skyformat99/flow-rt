module flow.core.util;

import flow.core.data;

import std.traits, std.range, std.uuid, std.datetime, std.stdio, std.ascii, std.conv;

/// Returns: full qualified name of type
template fqn(T) {
    enum fqn = fullyQualifiedName!T;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}

mixin template error() {
    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.type);
    }
}

mixin template exception() {
    override @property string type() {return fqn!(typeof(this));}

    Exception[] inner;

    this(string msg = string.init, Data d = null, Exception[] i = null) {
        super(msg != string.init ? msg : this.type);
        this.data = d;
        this.inner = i;
    }
}

class FlowError : Error {
	abstract @property string type();

    package this(string msg) {super(msg);}
}

class FlowException : Exception {
	abstract @property string type();
    Data data;

    this(string msg) {super(msg);}
}

class ProcessError : FlowError {mixin error;}

class TickException : FlowException {mixin exception;}
class EntityException : FlowException {mixin exception;}
class SpaceException : FlowException {mixin exception;}
class ProcessException : FlowException {mixin exception;}
class JunctionException : FlowException {mixin exception;}

class NotImplementedError : FlowError {mixin error;}

package class InvalidStateException : FlowException {mixin exception;}
package class StateRefusedException : FlowException {mixin exception;}

/// state machine mixin template
package abstract class StateMachine(T) if (isScalarType!T) {
    import core.sync.rwmutex;

    private ReadWriteMutex _lock;
    protected @property ReadWriteMutex lock(){return this._lock;}
    private T _state;

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
    import std.stdio;
    writeln("testing state machine");

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

enum LL : uint {
    Message = 1 << 0,
    Fatal = 1 << 1,
    Error = 1 << 2,
    Warning = 1 << 3,
    Info = 1 << 4,
    Debug = 1 << 5,
    FDebug = 1 << 6
}

class Log {
    public static immutable sep = newline~"--------------------------------------------------"~newline;
    public static LL logLevel = LL.Message | LL.Fatal | LL.Error | LL.Warning | LL.Info | LL.Debug;

    private static string get(string str) {
        if(str != string.init)
            return str~newline~"    ";
        else return string.init;
    }

    private static string get(Throwable thr) {
        string str;

        if(thr !is null) {
            str ~= thr.file~":"~thr.line.to!string;

            if(thr.msg != string.init)
                str ~= "("~thr.msg~newline~")";

            str ~= newline~thr.info.to!string;
        }

        if(thr.as!FlowException !is null && thr.as!FlowException.data !is null) {
            str ~= sep;
            str ~= thr.as!FlowException.data.json(true)~newline;
            str ~= sep;
            str ~= sep;
        }

        return str;
    }

    private static string get(Data d) {
        return Log.sep~(d !is null ? d.json(true) : "NULL");
    }

    public static void msg(LL level, string msg) {
        Log.msg(level, msg, null, null.as!Data);
    }

    public static void msg(LL level, string msg, Throwable thr) {
        Log.msg(level, msg, thr, null.as!Data);
    }
    
    public static void msg(DT)(LL level, string msg, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, msg, null, dIn);
    }

    public static void msg(LL level, Throwable thr) {
        Log.msg(level, string.init, thr, null.as!Data);
    }

    public static void msg(DT)(LL level, Throwable thr, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, string.init, thr, dIn);
    }

    public static void msg(DT)(LL level, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        Log.msg(level, string.init, null, dIn);
    }

    public static void msg(DT)(LL level, string msg, Throwable thr, DT dIn) if(is(DT : Data) || (isArray!DT && is(ElementType!DT:Data))) {
        if(level & logLevel) {
            string str = Log.get(msg);
            str ~= Log.get(thr);
            static if(isArray!DT) {
                foreach(d; dIn)
                    str ~= Log.get(d);
            } else str ~= Log.get(dIn);
            Log.print(level, str);
        }
    }

    private static void print(LL level, string msg) {
        auto str = "["~level.to!string~"] ";
        str ~= msg;

        synchronized {
            writeln(str);
            //flush();
        }
    }
}

import core.atomic;
/* Atomics code.  These forward to core.atomic, but are written like this
   for two reasons:
   1.  They used to actually contain ASM code and I don' want to have to change
       to directly calling core.atomic in a zillion different places.
   2.  core.atomic has some misc. issues that make my use cases difficult
       without wrapping it.  If I didn't wrap it, casts would be required
       basically everywhere.
*/
package void atomicSetUbyte(T)(ref T stuff, T newVal)
if (__traits(isIntegral, T) && is(T : ubyte))
{
    //core.atomic.cas(cast(shared) &stuff, stuff, newVal);
    atomicStore(*(cast(shared) &stuff), newVal);
}

package ubyte atomicReadUbyte(T)(ref T val)
if (__traits(isIntegral, T) && is(T : ubyte))
{
    return atomicLoad(*(cast(shared) &val));
}

// This gets rid of the need for a lot of annoying casts in other parts of the
// code, when enums are involved.
package bool atomicCasUbyte(T)(ref T stuff, T testVal, T newVal)
if (__traits(isIntegral, T) && is(T : ubyte))
{
    return core.atomic.cas(cast(shared) &stuff, testVal, newVal);
}