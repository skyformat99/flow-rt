module flowbase.listener.types;

import core.time;
import core.thread;
import core.sync.mutex;

import flowbase.type.interfaces;
import flowbase.entity.interfaces;
import flowbase.task.interfaces;
import flowbase.signal.interfaces;

abstract class Listener : Thread
{
    private Mutex _lock;
    private Duration _waitAtBreak;
    private IFiFo!IFlowSignal _queue;

    private IEntity _entity;
    @property IEntity entity(){return this._entity;}

    abstract @property string[] acceptedSignals();

    this(IEntity entity, Duration waitAtBreak = 50.msecs)
    {
        this._lock = new Mutex;
        this._waitAtBreak = waitAtBreak;
        this._entity = entity;
        // TODO this._queue = new FiFo;

        super(&this.run);
    }

    void run()
    {
        IFlowSignal signal;
        synchronized(this._lock)
        {
            signal = this._queue.pop();
        }

        if(signal !is null)
        {
            auto task = this.GetTask(signal);
            auto allowed = task !is null;

            if(is(signal : IUnicastSignal))
            {
                if(allowed)
                    allowed = (cast(IUnicastSignal)signal).accept(this.entity.reference);
                else
                    (cast(IUnicastSignal)signal).refuse(this.entity.reference);
            }

            if(allowed)
            {
                if(task !is null)
                    this.entity.createTasker(task);
            }
        }
        else Thread.sleep(this._waitAtBreak);   

        this.run();
    }

    void receive(IFlowSignal signal)
    {
        synchronized(this._lock)
            this._queue.put(signal);
    }

    abstract ITask GetTask(IFlowSignal signal);
} 