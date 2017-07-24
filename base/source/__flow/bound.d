module __flow.bound;

import __flow.util, __flow.tasker, __flow.data, __flow.tick;
import flow.base.data;

import core.sync.rwmutex;

package enum EntityState {
    Frozen = 0,
    Ticking,
    Damaged
}

package class Bound : StateMachine!EntityState {
    ReadWriteMutex sync;
    Tasker tasker;
    EntityMeta entity;
    Exception[] errors;
    Ticker[] ticker;

    this(Tasker t, EntityMeta e) {
        this.sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this.tasker = t;
        this.entity = e;
    }

    bool send(Signal s) {
        return false;
    }
}