module __flow.executor;

import std.parallelism;

package class Executor {
    private TaskPool tp;

    this(size_t worker) {
        this.tp = new TaskPool(worker);
    }

    void exec(void delegate() t) {
        this.tp.put(task(t));
    }
}