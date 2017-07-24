module __flow.executor;

import __flow.util, __flow.error;

import core.time;
import std.parallelism;

package enum ExecutorState {
    Stopped = 0,
    Started
}

package class Executor : StateMachine!ExecutorState {
    private size_t worker;
    private TaskPool tp;

    this(size_t worker) {
        this.worker = worker;
    }

    override protected bool onStateChanging(ExecutorState o, ExecutorState n) {
        switch(n) {
            case ExecutorState.Started:
                return o == ExecutorState.Stopped;
            case ExecutorState.Stopped:
                return o == ExecutorState.Started;
            default: return false;
        }
    }

    override protected void onStateChanged(ExecutorState o, ExecutorState n) {
        switch(n) {
            case ExecutorState.Started:
                this.tp = new TaskPool(this.worker);
                break;
            case ExecutorState.Stopped:
                if(this.tp !is null)
                    this.tp.finish(true); // we need to block until there are no tasks executed anymore
                break;
            default: break;
        }
    }

    void start() {
        this.state = ExecutorState.Started;
    }

    void stop() {
        this.state = ExecutorState.Stopped;
    }

    void exec(void delegate() t, Duration d = Duration.init) {
        this.ensureState(ExecutorState.Started);

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

version(unittest) class ExecutorTest {
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
    auto t = new ExecutorTest;
    auto e = new Executor(1);
    e.start();

    try {
        e.exec(&t.set1);
        e.exec(&t.set2);
        e.exec(&t.set3);
    } finally {
        e.stop();
    }

    assert(t.t3 > t.t2 && t.t2 > t.t1, "tasks were not executed in right order");
}