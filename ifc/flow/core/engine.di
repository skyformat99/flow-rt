// D import file generated from './flow/core/engine.d'
module flow.core.engine;
import flow.core.util;
import flow.core.data;
import flow.std;
import core.thread;
import core.sync.rwmutex;
import std.uuid;
import std.string;
private enum SystemState 
{
	Created = 0,
	Ticking,
	Frozen,
	Disposed,
}
public class TickMeta : Data
{
	mixin data!();
	mixin field!(TickInfo, "info");
	mixin field!(Signal, "trigger");
	mixin field!(TickInfo, "previous");
	mixin field!(Data, "data");
}
abstract class Tick
{
	private TickMeta meta;
	private Entity entity;
	private Ticker ticker;
	protected @property TickInfo info();
	protected @property Signal trigger();
	protected @property TickInfo previous();
	protected @property Data data();
	protected @property ReadWriteMutex sync();
	protected @property Data context();
	public @property bool accept();
	public @property size_t costs();
	public void run();
	public void error(Throwable thr);
	protected bool next(string tick, Data data = null);
	protected bool fork(string tick, Data data = null);
	protected EntityController get(EntityPtr entity);
	private EntityController get(string e);
	protected EntityController spawn(EntityMeta entity);
	protected void kill(EntityPtr entity);
	private void kill(string e);
	protected void register(string signal, string tick);
	protected void deregister(string signal, string tick);
	protected bool send(Unicast signal, EntityPtr entity = null);
	protected bool send(Anycast signal);
	protected bool send(Multicast signal, string space = string.init);
}
private bool checkAccept(Tick t);
void msg(Tick t, LL level, string msg);
void msg(Tick t, LL level, Throwable thr, string msg = string.init);
void msg(Tick t, LL level, Data d, string msg = string.init);
private void die(Tick t, string msg);
private void die(Tick t, Exception ex, string msg = string.init);
private void die(Tick t, Data d, string msg = string.init);
TickMeta createTickMeta(EntityMeta entity, string type, UUID group = randomUUID);
private Tick createTick(TickMeta m, Entity e);
private class Ticker : StateMachine!SystemState
{
	bool detaching;
	UUID id;
	Entity entity;
	Tick actual;
	Tick coming;
	Exception error;
	private this(Entity b)
	{
		this.id = randomUUID;
		this.entity = b;
		super();
	}
	this(Entity b, Tick initial)
	{
		this(b);
		this.coming = initial;
		this.coming.ticker = this;
	}
	~this();
	void start(bool detaching = true);
	void join();
	void stop();
	void dispose();
	void detach();
	protected override bool onStateChanging(SystemState o, SystemState n);
	protected override void onStateChanged(SystemState o, SystemState n);
	void tick();
	void runTick();
}
private void msg(Ticker t, LL level, string msg);
private void msg(Ticker t, LL level, Throwable thr, string msg = string.init);
private void msg(Ticker t, LL level, Data d, string msg = string.init);
class EntityMeta : Data
{
	mixin data!();
	mixin field!(EntityPtr, "ptr");
	mixin field!(EntityAccess, "access");
	mixin field!(Data, "context");
	mixin array!(Event, "events");
	mixin array!(Receptor, "receptors");
	mixin array!(TickMeta, "ticks");
}
private class Entity : StateMachine!SystemState
{
	ReadWriteMutex sync;
	ReadWriteMutex metaLock;
	Space space;
	EntityMeta meta;
	Ticker[UUID] ticker;
	this(Space s, EntityMeta m)
	{
		this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
		this.metaLock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
		m.ptr.space = s.meta.id;
		this.meta = m;
		this.space = s;
		super();
	}
	~this();
	void detach(Ticker t);
	void freeze();
	void tick();
	void dispose();
	void register(string s, string t);
	void deregister(string s, string t);
	void register(EventType et, string t);
	void deregister(EventType et, string t);
	bool receipt(Signal s);
	bool start(Tick t);
	bool send(Unicast s);
	bool send(Anycast s);
	bool send(Multicast s);
	EntityMeta snap();
	protected override bool onStateChanging(SystemState o, SystemState n);
	protected override void onStateChanged(SystemState o, SystemState n);
}
string addr(EntityPtr e);
class EntityController
{
	private Entity _entity;
	@property EntityPtr entity();
	@property SystemState state();
	private this(Entity e)
	{
		this._entity = e;
	}
	void freeze();
	void tick();
	EntityMeta snap();
}
private bool matches(Space space, string pattern);
class SpaceMeta : Data
{
	mixin data!();
	mixin field!(string, "id");
	mixin array!(EntityMeta, "entities");
}
class Space : StateMachine!SystemState
{
	private SpaceMeta meta;
	private Process process;
	private Entity[string] entities;
	private this(Process p, SpaceMeta m)
	{
		this.meta = m;
		this.process = p;
		super();
		this.init();
	}
	~this();
	private void init();
	void freeze();
	void tick();
	void dispose();
	SpaceMeta snap();
	EntityController get(string e);
	EntityController spawn(EntityMeta m);
	void kill(string e);
	private bool route(Unicast s);
	private bool route(Anycast s);
	private bool route(Multicast s, bool intern = false);
	private bool send(Unicast s);
	private bool send(Anycast s);
	private bool send(Multicast s);
	protected override bool onStateChanging(SystemState o, SystemState n);
	protected override void onStateChanged(SystemState o, SystemState n);
}
class Process
{
	private ProcessConfig config;
	private Tasker tasker;
	private Space[string] spaces;
	this(ProcessConfig c = null)
	{
		import core.cpuid;
		if (c is null)
			c = new ProcessConfig;
		if (c.worker < 1)
			c.worker = threadsPerCPU > 1 ? threadsPerCPU - 1 : 1;
		this.config = c;
		this.tasker = new Tasker(c.worker);
		this.tasker.start();
	}
	~this();
	private bool shift(Unicast s);
	private bool shift(Anycast s);
	private bool shift(Multicast s);
	private void ensureThread();
	Space add(SpaceMeta s);
	Space get(string s);
	void remove(string s);
}
version (unittest)
{
	class TestTickException : FlowException
	{
		mixin exception!();
	}
	class TestSignal : Unicast
	{
		mixin data!();
	}
	class TestTickContext : Data
	{
		mixin data!();
		mixin field!(size_t, "cnt");
		mixin field!(string, "error");
		mixin field!(bool, "forked");
		mixin field!(TickInfo, "info");
		mixin field!(TestTickData, "data");
		mixin field!(TestSignal, "trigger");
		mixin field!(bool, "onCreated");
		mixin field!(bool, "onTicking");
		mixin field!(bool, "onFrozen");
	}
	class TestTickData : Data
	{
		mixin data!();
		mixin field!(size_t, "cnt");
	}
	class TestTick : Tick
	{
		import flow.core.util;
		override void run();
		override void error(Throwable thr);
	}
	class TestOnCreatedTick : Tick
	{
		override void run();
	}
	class TestOnTickingTick : Tick
	{
		override void run();
	}
	class TestOnFrozenTick : Tick
	{
		override void run();
	}
	class TriggeringTestContext : Data
	{
		mixin data!();
		mixin field!(EntityPtr, "target");
	}
	class TriggeringTestTick : Tick
	{
		override void run();
	}
	SpaceMeta createTestSpace();
	EntityMeta createTestEntity();
	EntityMeta createTriggerTestEntity(EntityPtr te);
}
