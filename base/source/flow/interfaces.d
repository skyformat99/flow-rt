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
    @property void id(UUID);
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
interface IFlowSignal : IData, IIdentified, IGrouped, ITyped
{
    @property EntityRef source();
    @property void source(EntityRef);
}

/** describes a multicast signal (for broadcasting leave domain empty)
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IMulticast : IFlowSignal
{
    @property string domain();
    @property void domain(string);
}

/** describes an anycast signal
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IAnycast : IFlowSignal
{
    @property string domain();
}

/** describes an unicast signal
please see <a href="https://github.com/RalphBariz/flow/blob/master/doc/specification.md#signal">specification - signaling</a>*/
interface IUnicast : IFlowSignal
{
    @property EntityRef destination();
    @property void destination(EntityRef);
}

interface ITriggerAware
{
    @property IFlowSignal trigger();
    //@property T trigger(T)();
    @property void trigger(IFlowSignal);
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
    UUID beginListen(string s, Object function(IEntity, IFlowSignal) h);
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
    bool answer(IFlowSignal);

    /// sends a signal into the swarm
    bool send(IFlowSignal);
}

/// scopes an entity can have
enum EntityScope
{
    Process,
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
    UUID beginListen(string s, Object function(IEntity, IFlowSignal) h);
    // entity stops listen at
    void endListen(UUID id);

    /// gets process the entity runs in
    @property IFlowProcess process();
    /// sets process the entity runs in
    @property void process(IFlowProcess);

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
    bool receive(IFlowSignal);
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
interface IOrgan
{
    @property IFlowProcess process();
    @property void process(IFlowProcess);

    @property IData config();
    @property IData context();

    void create();
    void dispose();
    
    bool finished();
}

/// describes a flow process
interface IFlowProcess
{
    /// reference of the process
    @property ProcessRef reference();

    /// get if tracing is enabled
    @property bool tracing();
    /// enable/disable tracing
    @property void tracing(bool);
    
    /// adds an entity
    UUID add(IEntity);
    
    /// adds an organ
    void add(IOrgan);

    /// removes an entity
    void remove(UUID);

    /// removes an organ
    void remove(IOrgan);

    /// gets the entity with [id]
    IEntity get(UUID id);

    /// process recieves a certain {signal] for a certain [entity] 
    bool receive(IFlowSignal, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    bool deliver(IUnicast, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    void deliver(IMulticast, EntityRef);

    /** process delivers a certain [signal]
    to a certain interceptor and/or [entity] */
    bool deliver(IAnycast, EntityRef);
    
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

    /// stops process
    void stop();

    // wait for finish
    void wait();

    // wait for finish
    void wait(bool delegate() expr);

    /// gets possible receivers for a certain [signal]
    InputRange!EntityInfo getReceiver(string);

    /** gets the local entities/interceptors
    listening to a [signal] */
    EntityInfo[] getListener(string);
}