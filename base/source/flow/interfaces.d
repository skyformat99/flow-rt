module flow.interfaces;

import core.sync.mutex;
import std.uuid, std.range.interfaces;

import flow.lib.vibe.data.json;
import flow.base.event, flow.base.type;
import flow.data;

interface ITyped
{
    @property string type();
    @property void type(string);
}

interface IStealth{}

interface IQuiet{}

interface ISync{}

interface IIdentified
{
    @property UUID id();
}

interface IGrouped
{
    @property UUID group();
    @property void group(UUID);
}

/// data property informations
struct PropertyInfo
{
	TypeInfo typeInfo;
	bool isList;
	bool isData;
}

/// interface describing data objects
interface IData : __IFqn
{
	@property string dataType();
	@property shared(PropertyInfo[string]) dataProperties();

	@property EPropertyChanging propertyChanging();
	@property EPropertyChanged propertyChanged();

	/// get the value of a data field by its name
	Object getGeneric(string);

	/// set the value of a data field by its name
	bool setGeneric(string, Object);

	string toJson();

	void fillFromJson(Json j);

	IData clone();
}

/** describes the abstract basic signal
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface ISignal : IData, IGrouped, ITyped
{
    @property UUID id();
    @property void id(UUID);
    @property EntityRef source();
    @property void source(EntityRef);
}

/** describes a multicast signal (for broadcasting leave domain empty)
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IMulticast : ISignal
{
    @property string domain();
    @property void domain(string);
}

/** describes an anycast signal
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IAnycast : ISignal
{
    @property string domain();
}

/** describes an unicast signal
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IUnicast : ISignal
{
    @property EntityRef destination();
    @property void destination(EntityRef);
}

interface ITriggerAware
{
    @property ISignal trigger();
    //@property T trigger(T)();
    @property void trigger(ISignal);
}

/// describes a ticker executing tchains of ticks
interface ITicker : IIdentified, ITriggerAware
{
    /// creates a new ticker initialized with given tick
    void fork(string tick, IData data = null);

    /// creates a new ticker initialized with given tick
    void fork(ITick);

    /// enques next tick in the chain
    void next(string tick, IData data = null);

    // entity starts listen at
    UUID beginListen(string s, Object function(IEntity, ISignal) h);
    // entity stops listen at
    void endListen(UUID id);

    /// enques next tick in the chain
    //void next(ITick);

    /// enques same tick in the chain
    void repeat();

    /// creates a new ticker initialized with same tick
    void repeatFork();

    /// starts ticker
    void start();

    /// stops ticker
    void stop();
}

/// describes a tick
interface ITick : __IFqn, IIdentified, IGrouped, ITriggerAware
{
    @property IEntity entity();
    @property void entity(IEntity);
    
    @property ITicker ticker();
    @property void ticker(ITicker);
    
    @property ITick previous();
    @property void previous(ITick);
    
    @property IData data();

    void run();

    void error(Exception);
    
    /// sends a unicast signal to a specific receiver
    bool send(IUnicast, EntityRef);
    /// sends a unicast signal to a specific receiver
    bool send(IUnicast, EntityInfo);
    /// sends a unicast signal to a specific receiver
    bool send(IUnicast, IEntity);

    /// sends a signal into the swarm
    bool answer(ISignal);

    /// sends a signal into the swarm
    bool send(ISignal);
}

/// scopes an entity can have
enum EntityScope
{
    Local,
    Global
}

// states an entity can have
enum EntityState
{
    Halted,
    Running,
    Sleeping
}

/// describes an entity
interface IEntity : __IFqn, IIdentified
{
    /// indicates if the entity is running
    @property bool running();

    /// entity wide lock for synchronization
    @property Mutex lock();
    
    /// the entities context
    @property Object context();
    
    // entity starts listen at
    UUID beginListen(string s, Object function(IEntity, ISignal) h);
    // entity stops listen at
    void endListen(UUID id);

    /// gets hull the entity runs in
    @property IHull hull();

    void create();
    void dispose();

    /// starts up entity
    void start();

    /// stops entity
    void stop();

    /// info to the entity
    @property EntityInfo info();

    /** recieve a signal and pass it to the adequate listener
    (usually called by a process)
    returns if signal was accepted */
    bool receive(ISignal);
}

/// describes an entity able to invoke
interface IInvokingEntity : IEntity
{
    /// invoke whatever is to invoke (usually called by a listener)
    void invoke(Object);
}

/// describes an entity able to invoke and handle ticks
interface ITickingEntity : IInvokingEntity
{
    /// the number of running ticks
    @property size_t count();

    /// run a tick (usually called by entities invoke)
    void invokeTick(ITick);
}

/// describes a tick
interface IOrgan : __IFqn, IIdentified
{
    @property IHull hull();
    @property void hull(IHull);

    @property IData config();
    @property IData context();

    void create();
    void dispose();
    
    bool finished();
}

interface IHull
{
    /// reference of the process
    @property FlowRef flow();
    /// get if tracing is enabled
    @property bool tracing();

    /// adds an entity
    UUID add(IEntity);
    /// removes an entity
    void remove(UUID);
    /// gets the entity with [id]
    IEntity get(UUID id);
    
    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(IUnicast, EntityRef);
    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(IUnicast, EntityInfo);
    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(IUnicast, IEntity);

    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(IUnicast);
    /** process sends a [signal] into the swarm
    returns true if any destination found */
    bool send(IMulticast);
    /** process sends a [signal] into the swarm
    returns true if any destination accepted
    (take care, blocks until anyone accepted it
    or noone was found or willing) */
    bool send(IAnycast);

    // wait for finishing something
    void wait(bool delegate() expr);
}

/// describes a flow process
interface IFlow
{
    /// reference of the process
    @property FlowRef reference();

    /// get if tracing is enabled
    @property bool tracing();
       
    /// adds an organ
    void add(IOrgan);

    /// removes an organ
    void remove(IOrgan);

    /// process recieves a certain {signal] for a certain [entity] 
    //bool receive(ISignal, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    //bool deliver(IUnicast, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    //void deliver(IMulticast, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    //bool deliver(IAnycast, EntityRef);

    // wait for finishing something
    void wait(bool delegate() expr);

    // wait for finish
    void wait();

    /// stops process
    void stop();

    /// gets possible receivers for a certain [signal]
    //InputRange!EntityInfo getReceiver(string);

    /** gets the local entities/interceptors
    listening to a [signal] */
    //EntityInfo[] getListener(string);
}