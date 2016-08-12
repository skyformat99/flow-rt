module flowbase.entity.interfaces;
import flowbase.entity.types;
import flowbase.entity.signals;

import flowbase.task.interfaces;
import flowbase.listener.interfaces;
import flowbase.signal.interfaces;

/// defines an available resource
interface IResource
{
    @property string id();
    @property uint available();
    @property uint total();
}

/// defines a resource requirement
interface IResourceReq
{
    @property string id();
    @property uint required();

    bool eval(IResource);
}

/// scopes an entity can have
enum EntityScope
{
    Process,
    Device,
    Global
}

// states an entity can have
enum EntityState
{
    Halted,
    Running,
    Sleeping
}

/// defines a entity manager managing entities inside a process
interface IEntityManager
{
    void add(IEntity);

    void run();

    IEntityRef getRef(IEntity);

    IEntityRef[] get(string);

    void signal(IEntityRef, IFlowSignal);
}

/// defines a entity setializer able to save and restore the state of an entity
interface IEntitySerializer
{
    string serializerToJson();
    byte[] serializerToBinary();
    void deserialize(string json);
    void deserialize(byte[] binary);
}

/// defines a reference to an entity, its apperance depends on the used communication channel
interface IEntityRef
{
    @property string id();
    @property string domain();
    @property IResource[] resources();
    @property string[] acceptedSignals();
}

/// defines an entity
interface IEntity
{
    @property IEntityManager manager();
    @property IListener listener();
    @property IEntitySerializer serializer();

    @property string id();
    @property string domain();
    @property IEntityRef reference();
    @property IResource[] resources();
    @property string[] acceptedSignals();

    @property EntityScope availability();    
    @property EntityState state();
    @property SStateChanged stateChanged();

    void start();
    void start(string json);
    void start(byte[] binary);

    void sleep();
    void wake();

    void stop();

    void createTasker(ITask task);
}