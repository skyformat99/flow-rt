module __flow.bound;

import __flow.tasker, __flow.data;
import flow.base.data;

import core.sync.rwmutex;

package struct Bound {
    ReadWriteMutex sync;
    Tasker tasker;
    EntityMeta entity;
    Exception[] errors;

    this(Tasker r, EntityMeta e) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.tasker = tasker;
        this.entity = e;
    }

    bool send(Signal s) {
        return false;
    }
}