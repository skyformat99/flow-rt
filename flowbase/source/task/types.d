module flowbase.task.types;
import flowbase.task.interfaces;

import core.thread;

import flowbase.entity.interfaces;

class Tasker : Thread, ITasker
{
    private bool _shouldBreak = false;

    private IEntity _entity;
    @property IEntity entity(){return this._entity;}

    private ITask _actual;
    @property ITask actual(){return this._actual;}

    private bool _isSleeping = false;
    @property bool isSleeping(){return this._isSleeping;}

    this(IEntity entity, ITask initTask)
    {
        this._entity = entity;
        this._actual = initTask;
        this.actual.entity = this.entity;

        super(&this.run);
    }

    void run()
    {
        auto newTask = this.actual.run();
        newTask.entity = this.entity;

        if(newTask !is null)
        {
            this._actual = newTask;

            if(!this._shouldBreak)
                this.run();
            else
                this._shouldBreak = false;
        }
    }
}

abstract class Task : ITask
{
    private IEntity _entity;
    @property IEntity entity(){return this._entity;}
    @property void entity(IEntity value){this._entity = value;}

    abstract ITask run();
}