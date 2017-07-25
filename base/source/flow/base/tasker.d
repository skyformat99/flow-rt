module flow.base.tasker;

import flow.base.util;

import core.time;
import std.parallelism;

package enum TaskerState {
    Stopped = 0,
    Started
}

package class Tasker : StateMachine!TaskerState {
    private size_t worker;
    private TaskPool tp;

    this(size_t worker) {
        this.worker = worker;
    }

    override protected bool onStateChanging(TaskerState o, TaskerState n) {
        switch(n) {
            case TaskerState.Started:
                return o == TaskerState.Stopped;
            case TaskerState.Stopped:
                return o == TaskerState.Started;
            default: return false;
        }
    }

    override protected void onStateChanged(TaskerState o, TaskerState n) {
        switch(n) {
            case TaskerState.Started:
                this.tp = new TaskPool(this.worker);
                break;
            case TaskerState.Stopped:
                if(this.tp !is null)
                    this.tp.finish(true); // we need to block until there are no tasks running anymore
                break;
            default: break;
        }
    }

    void start() {
        this.state = TaskerState.Started;
    }

    void stop() {
        this.state = TaskerState.Stopped;
    }

    void run(void delegate() t, Duration d = Duration.init) {
        this.ensureState(TaskerState.Started);

        if(d == Duration.init)
            this.tp.put(task(t));
        else {
            throw new NotImplementedError;
            /*synchronized(this.delayedLock) {
                auto target = MonoTime.currTime + d;
                this.delayed[target] ~= t;
            }*/
        }
    }
}

version(unittest) class TaskerTest {
    MonoTime t1;
    MonoTime t2;
    MonoTime t3; 

    void set1() {
        t1 = MonoTime.currTime;
    }

    void set2() {
        t2 = MonoTime.currTime;
    }

    void set3() {
        t3 = MonoTime.currTime;
    }
}

unittest {
    auto t = new TaskerTest;
    auto e = new Tasker(1);
    e.start();

    try {
        e.run(&t.set1);
        e.run(&t.set2);
        e.run(&t.set3);
    } finally {
        e.stop();
    }

    assert(t.t3 > t.t2 && t.t2 > t.t1, "tasks were not executed in right order");
}