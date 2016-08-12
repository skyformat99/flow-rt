module flowbase.task.interfaces;

import flowbase.entity.interfaces;

interface ITasker
{
    @property ITask actual();
    @property IEntity entity();
    @property bool isSleeping();

    void run();
}

interface ITask
{
    @property IEntity entity();
    @property void entity(IEntity);

    ITask run();
}