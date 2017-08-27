// D import file generated from './flow/core/util.d'
module flow.core.util;
import flow.core.data;
import std.traits;
import std.range;
import std.uuid;
import std.datetime;
import std.stdio;
import std.ascii;
import std.conv;
enum fqn(T) = fullyQualifiedName!T;
T as(T, S)(S sym)
{
	return cast(T)sym;
}
template error()
{
	override @property string type()
	{
		return fqn!(typeof(this));
	}
	this(string msg = string.init)
	{
		super(msg != string.init ? msg : this.type);
	}
}
template exception()
{
	override @property string type()
	{
		return fqn!(typeof(this));
	}
	Exception[] inner;
	this(string msg = string.init, Data d = null, Exception[] i = null)
	{
		super(msg != string.init ? msg : this.type);
		this.data = d;
		this.inner = i;
	}
}
class FlowError : Error
{
	abstract @property string type();
	package this(string msg)
	{
		super(msg);
	}
}
class FlowException : Exception
{
	abstract @property string type();
	Data data;
	this(string msg)
	{
		super(msg);
	}
}
class ProcessError : FlowError
{
	mixin error!();
}
class TickException : FlowException
{
	mixin exception!();
}
class EntityException : FlowException
{
	mixin exception!();
}
class SpaceException : FlowException
{
	mixin exception!();
}
class ProcessException : FlowException
{
	mixin exception!();
}
class NotImplementedError : FlowError
{
	mixin error!();
}
package class InvalidStateException : FlowException
{
	mixin exception!();
}
package class StateRefusedException : FlowException
{
	mixin exception!();
}
package abstract class StateMachine(T) if (isScalarType!T)
{
	import core.sync.rwmutex;
	private ReadWriteMutex _lock;
	protected @property ReadWriteMutex lock()
	{
		return this._lock;
	}
	private T _state;
	@property T state()
	{
		return this._state;
	}
	protected @property void state(T value)
	{
		auto allowed = false;
		T oldState;
		synchronized(this.lock.writer) {
			if (this._state != value)
			{
				allowed = this.onStateChanging(this._state, value);
				if (allowed)
				{
					oldState = this._state;
					this._state = value;
				}
			}
		}
		if (allowed)
			this.onStateChanged(oldState, this._state);
		else
			throw new StateRefusedException;
	}
	protected this()
	{
		this._lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
		this.onStateChanged(this.state, this.state);
	}
	protected void ensureState(T requiredState)
	{
		if (this._state != requiredState)
			throw new InvalidStateException;
	}
	protected void ensureStateOr(T state1, T state2)
	{
		auto state = this._state;
		if (state != state1 && state != state2)
			throw new InvalidStateException;
	}
	protected void ensureStateOr(T state1, T state2, T state3)
	{
		auto state = this._state;
		if (state != state1 && state != state2 && state != state3)
			throw new InvalidStateException;
	}
	protected void ensureStateOr(T state1, T state2, T state3, T state4)
	{
		auto state = this._state;
		if (state != state1 && state != state2 && state != state3 && state != state4)
			throw new InvalidStateException;
	}
	protected bool onStateChanging(T oldState, T newState)
	{
		return true;
	}
	protected void onStateChanged(T oldState, T newState)
	{
	}
}
version (unittest)
{
	enum TestState 
	{
		State1,
		State2,
		State3,
	}
	class TestStateMachine : StateMachine!TestState
	{
		int x;
		bool state1Set;
		bool state2Set;
		bool state3Set;
		protected override bool onStateChanging(TestState oldState, TestState newState);
		protected override void onStateChanged(TestState oldState, TestState newState);
		void onState1();
		void onState2();
		void onState3();
		bool canSwitchToState3();
		bool CheckState(TestState s);
		bool CheckIllegalState(TestState s);
		bool CheckSwitch(TestState s);
		bool CheckIllegalSwitch(TestState s);
	}
}
enum LL : uint
{
	Message = 1 << 0,
	Fatal = 1 << 1,
	Error = 1 << 2,
	Warning = 1 << 3,
	Info = 1 << 4,
	Debug = 1 << 5,
	FDebug = 1 << 6,
}
class Log
{
	public static immutable sep = newline ~ "--------------------------------------------------" ~ newline;
	public static LL logLevel = LL.Message | LL.Fatal | LL.Error | LL.Warning | LL.Info | LL.Debug;
	public static void msg(LL level, string msg);
	public static void msg(LL level, Throwable thr, string msg = string.init);
	public static void msg(LL level, Data d, string msg = string.init);
}
import core.time;
import std.parallelism;
package enum TaskerState 
{
	Stopped = 0,
	Started,
}
package class Tasker : StateMachine!TaskerState
{
	private size_t worker;
	private TaskPool tp;
	this(size_t worker)
	{
		this.worker = worker;
	}
	protected override bool onStateChanging(TaskerState o, TaskerState n);
	protected override void onStateChanged(TaskerState o, TaskerState n);
	void start();
	void stop();
	void run(string id, size_t costs, void delegate() t, Duration d = Duration.init);
}
version (unittest)
{
	class TaskerTest
	{
		MonoTime t1;
		MonoTime t2;
		MonoTime t3;
		void set1();
		void set2();
		void set3();
	}
}
