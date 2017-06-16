module flow.base.interfaces;

import core.sync.mutex;
import std.uuid, std.range.interfaces;

import flow.lib.vibe.data.json;
import flow.flow.event, flow.flow.type;
import flow.base.data;

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
    @property string id();
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
    bool send(Unicast, EntityPtr);
    /// sends a unicast signal to a specific receiver
    bool send(Unicast, EntityInfo);
    /// sends a unicast signal to a specific receiver
    bool send(Unicast, IEntity);

    /// sends a signal into the swarm
    bool answer(Signal);

    /// sends a signal into the swarm
    bool send(Signal);
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
    @property IData context();
    
    // entity starts listen at
    UUID beginListen(string s, Object function(IEntity, Signal) h);
    // entity stops listen at
    void endListen(UUID id);

    /// gets hull the entity runs in
    @property IHull hull();

    void create();
    void dispose();

    /// starts up entity
    void start();

    /** stops an entity. be cautious.
        the philosophy is, stopping an entity does not change it.
        as soon as it gets started, it should continue to do whatever it did.
        it "memory" is its context which is serialized and stored*/
    void stop();

    /// info to the entity
    @property EntityInfo info();

    /** recieve a signal and pass it to the adequate listener
    (usually called by a process)
    returns if signal was accepted */
    bool receive(Signal);
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

interface IHull
{
    /// ptr of the process
    @property FlowPtr flow();
    /// get if tracing is enabled
    @property bool tracing();

    /// adds an entity
    EntityInfo spawn(EntityInfo, IData);
    /// removes an entity
    IData kill(EntityInfo);
    /// gets the entity with [id]
    IEntity get(EntityInfo);
    
    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(Unicast, EntityPtr);

    /** process sends a [signal] into the swarm
    returns true if destination found */
    bool send(Unicast);
    /** process sends a [signal] into the swarm
    returns true if any destination found */
    bool send(Multicast);
    /** process sends a [signal] into the swarm
    returns true if any destination accepted
    (take care, blocks until anyone accepted it
    or noone was found or willing) */
    bool send(Anycast);

    /// wait for something
    void wait(bool delegate() expr);

    /// freeze communication
    void freeze();

    /// unfreeze communication
    void unfreeze();
}

/// describes a flow process
interface IFlow
{
    /// ptr of the process
    @property FlowPtr ptr();

    /// get if tracing is enabled
    @property bool tracing();

    // wait for finishing something
    void wait(bool delegate() expr);

    /// stops process
    void stop();
}