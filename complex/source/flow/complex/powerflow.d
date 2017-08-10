module flow.complex.basicact;

import flow.base.data, flow.base.util, flow.base.engine, flow.base.std;

class Relation : Data {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(double, "power");
}

class Actuality : Data {
    mixin data;

    mixin field!(double, "power");
    mixin array!(Relation, "relations");
}

class Act : Unicast {
    mixin signal;

    mixin field!(double, "power");
}

class OnTick : Tick {
    override void run() {
        // on startup we calculate the power of actuality for each entity
        auto c = this.context.as!Actuality;

        c.power = 0.0;
        foreach(r; c.relations)
            c.power += r.power;
    }
}

class React : Tick {
    override void run() {
        import std.algorithm.mutation;

        auto s = this.trigger.as!Act;
        auto c = this.context.as!Actuality;

        auto req = s.power;

        synchronized(this.sync.writer) {
            // the requested power is dragged from the weakest relations in own actuality
            while(req != 0.0) {
                auto r = c.relations[$-1];

                // since we avoid recalculating power of own actuality ever again, we track changes
                if(r.power < req) {
                    c.power -= r.power;

                    req -= r.power;
                    c.relations = c.relations[0..$-1];
                } else if(r.power > req) {
                    c.power -= req;

                    r.power -= req;
                    req = 0.0;
                } else {
                    c.power = req;

                    req = 0.0;
                    c.relations = c.relations[0..$-1];
                }
            }
        }

    }
}

class Exist : Tick {
    override void run() {
        auto c = this.context.as!Actuality;

        synchronized(this.sync.writer) {
            // I request from each relation the adequate share of the own actuality
            foreach(r; c.relations) {
                auto addition = r.power/c.power;
                auto s = new Act;
                s.power = addition;
                if(this.send(s, r.entity)) {
                    r.power += addition;

                    // since we avoid recalculating power of own actuality ever again, we track changes
                    c.power += addition;
                }
            }
        }

        this.next(this.info.type);
    }
}