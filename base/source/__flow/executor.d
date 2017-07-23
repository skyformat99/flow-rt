module __flow.executor;

import core.time;
import std.parallelism;

package class Executor {
    private TaskPool tp;

    this(size_t worker) {
        this.tp = new TaskPool(worker);
    }

    void exec(void delegate() t) {//, Duration d = Duration.init) {
        //if(d == Duration.init)
            this.tp.put(task(t));
        //else {
            // TODO
        //}
    }
}