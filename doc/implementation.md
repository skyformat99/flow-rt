# Implementation
This text should provide a rough guideline for implementing the specifications.
It is not only meant for helping to implement compatible entities in different languages,
but also for helping me to focus my thoughts. I simply want to avoid refractoring again and again.

## Conventions
Since the first implementation will happen in D, the conventions are designed for that language.
For implementing FLOW in different languages the conventions may have to be adapted.

### Module naming
The library itself is called **flowbase**. It contains following **codedomain**s.
* **type**: the base types required for the implementation (SignalArgs, List, FiFo, etc.)
* **data**: the whole base code for the data handling(not data services).
* **task**: the whole base code for task handling and dispatching.
* **resource**: base code for resource definitions.
* **entity**: base functionality of the entities allowing them to be instanciated, managed, listening etc.

Each codedomain contains one or more of following D modules:
* **interfaces.d**: interface definitions.
* **exceptions.d**: error and exception types (throwables).
* **meta.d**: compile time templates/code generation.
* **signals.d**: signals and their aruguments(base is flowbase.type.types.SignalArgs).
* **templates.d**: shared implementations.
* **types.d**: type definitions and their implementation.
* **extensions.d**: methods extending type, struct and interface functionality
* **tests.d**: unit tests

### Code
#### Basic naming
Type and struct names as Compile Time Templates are written as UpperCamelCase.

In the opposite to whats common in D Phobos library interface names are begining with a capitalized "I" followed by an UpperCamelCase name.
For example IMyDefinition.

Signal names are beginning with a capitalized "S" followed by an UpperCamelCase name.
For example SCollectionChanged.

Template names are beginning with a capitalized "T" followed by an UpperCamelCase name.
For example TDataObject.

For satisfying naming conventions the required parts interfaces, templates and signals from the Phobos library are wrapped.
Also later this should guarantee flexibility up to a certain point.

#### Member naming
Private field and property names are beginning with a "_" followed by a lowerCamelCase name.

Public field, property and method names are written as lowerCamelCase.

## Basics
You define an executable this way:
```D
import mylib.entity.types;

int main()
{
    auto manager = new EntityManager();
    manager.add(new FooEntity());
    manager.add(new BarEntity());

    return manager.run();
}
```

As you can see, here you get an **entity manager** receiving entity instances before(but also after is possible) it enters the main loop.

## Entity
An entity is controllable by certain controll mechanisms like start(optional with deserialization), stop, break, continue, serialize, and for tasking entities enqueue.
All this basic functionality is defined by the abstract type flowbase.entity.types.Entity.

Sample entity base implementation:
```D
module flowbase.entity.types;

import core.time;
import flowbase.resource.interfaces;

abstract class Entity : IEntity
{
    private EntityManager _manager;
    @property EntityManager manager(){return this._manager;}

    private SignalCaster _caster = new SignalCaster(this);
    @property SignalCaster caster(){return this._caster;}

    @property Listener listener() {return null;}

    @property IResource[] resources() {return null;}

    @property EntityScope scope(){return EntityScope.Global;}
    @property IEntitySerializer serializer(){return null;}
    
    private EntityState _state;
    @property EntityState state() {return this._state;}
    protected @property void state(EntityState value)
    {
        if(this._state != value)
        {
            this._state = state;

            this.stateChanged.emit(this, new StateChangedSignalArgs());
        }
    }

    private SStateChanged _stateChanged = new SStateChanged();
    @property SStateChanged stateChanged()
    {
        return this._stateChanged;
    }

    abstract @property string domain();

    void start(string json = null)
    {
        if(json !is null)
        {
            if(this.serializer !is null)
                this.serializer.deserialize(json);
            else throw new IncompatibleRuntimeDataError(typeid(this), json);
        }

        this.onStart();
        this.state = EntityState.Running;
    }

    void break()
    {
        this.state = EntityState.Paused;
        while(this._dispatcher.IsRunning) Thread.sleep(50.msecs);
    }

    void continue()
    {
        this.state = EntityState.Running;
    }

    string stop()
    {   string json;
        if(this.serializer !is null)
           json = this.serializer.serialize();
          
        this.onStop();
        this.state = EntityState.Halted;
        
        return json;
    }

    protected void onStart(){}
    protected void onBreak(){}
    protected void onContinue(){}
    protected void onStop(){}

    string serialize()
    {
        return this.serializer !is null ? this.serializer.serialize() : null;
    }
}
```

Sample tasking entity base implementation:
```D
import core.thread;
import flowbase.task.types;

abstract class TaskingEntity : Entity, ITasking
{
    private List!TaskChain _taskChains = new List!TaskChain();

    protected void enqueue(ITask task)
    {
        auto chain = new TaskChain(this, task);
        this._taskChains.put(chain);
        chain.Run();
    }

    package void dispose(TaskChain chain)
    {
        this._taskChains.remove(chain);
    } 

    override string stop()
    {
        foreach(taskChain; this._taskChains)
            taskChain.Dispose();

        base.stop();
    }
}
```

Therefor a concrete implementation would look like:
```D
module mylib.entity.types;
import mylib.resource.types;
import mylib.task.types;
import mylib.listener.types;

import core.thread;
import core.time;
import flowbase.entity.types;
import flowbase.task.types;
import flowbase.resource.interfaces;
import flowbase.listener.types;

class FooEntity : TaskingEntity
{
    override
    {
        @property IResource[] resources()
        {
            IResource[] res;
            res ~= new CpuResource();
            return res;
        }

        private Listener _listener;
        @property Listener listener()
        {
            return this._listener;
        }

        @property string domain()
        {
            return "mydomain.mycategory";
        }

        void onStart()
        {
            this._listener = new FooListener();
        }

        void onStop()
        {
            // do some cleanup

            destroy(this._listener);
            this._listener = null;
        }
    }
}
```

### Data bag

