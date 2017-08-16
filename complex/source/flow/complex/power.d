module flow.complex.power;

import flow.base.data, flow.base.util, flow.base.engine, flow.base.std;

/// describes a powerdriven relation
class Relation : Data {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(double, "power");
}

/// describes the actuality of a power driven entity
class Actuality : Data {
    mixin data;

    mixin field!(double, "power");
    mixin array!(Relation, "relations");
}

/// signals an act of power
class Act : Unicast {
    mixin data;

    mixin field!(double, "power");
}

/// reaction of a power driven entity on an act of power
class React : Tick {
    override @property bool accept() {
        import std.math, std.array, std.algorithm.iteration, std.algorithm.sorting;

        auto s = this.trigger.as!Act;
        auto c = this.context.as!Actuality;

        // we only accept it, if its power is enough to make a difference
        synchronized(this.sync.writer) {
            auto newPower = c.power - s.power;
            if(!c.power.isIdentical(newPower)) {
                // if it makes a difference, we give this piece of power to requester
                c.power = newPower;

                // we increase the virtual power of requester
                auto r = c.relations.filter!(a=>a.entity == s.src).front;
                if(r is null) { // if we do not have a relation we create a new one
                    r = new Relation;
                    r.entity = s.src;
                    c.relations ~= r;
                }
                r.power += s.power;

                // now we sort the whole relations array for beeing able to iterate correctly
                c.relations = c.relations.sort!((a, b) => a.power < b.power).array;

                return true;
            } else return false;
        }
    }

    override void run() {
        import std.math;

        auto s = this.trigger.as!Act;
        auto d = new DoData;
        d.req = s.power;
        d.rest = d.req;
        d.excludes = [s.src];
        d.done = d.excludes;
        this.next("flow.complex.power.Do", d);
    }
}

class DoData : Data {
    mixin data;

    mixin field!(double, "req");
    mixin field!(double, "rest");
    mixin field!(double, "last");
    mixin array!(EntityPtr, "excludes");
    mixin array!(EntityPtr, "done");
}

class Do : Tick {
    override void run() {
        import std.math, std.algorithm.searching, std.algorithm.mutation;

        auto c = this.context.as!Actuality;
        auto d = this.data.as!DoData;

        EntityPtr done;
        synchronized(this.sync.writer) {
            // creating new act
            auto act = new Act;

            foreach_reverse(i, r;c.relations) {
                // do not handle it again
                if(!d.done.any!(a=>a == r.entity)) {
                    act.power = r.power * (r.power/d.req);
                    // if target can deliver power from own pov and its pov
                    if(act.power <= r.power && act.power <= d.rest && this.send(act, r.entity)) {
                        d.rest -= act.power;

                        // if from own pov there is power left just decrease
                        if(act.power < r.power)
                            r.power -= act.power;
                        else // if not, relation is delpleted and removed
                            c.relations.remove(i);
                    }

                    // however we did something and it has to go into next round
                    done = r.entity;
                    break;
                }
            }
        }

        if(done !is null)
            d.done ~= done;
        else // we have to continue at the beginning (can this case even happen?)
            d.done = d.excludes;

        /* if there is still something to do,
        do it as long as there is the chance to get it done */
        if(d.rest > 0.0 && !d.rest.isIdentical(d.last)) {
            d.last = d.rest;
            this.next("flow.complex.power.Do", d);
        }
    }
}

/// creates a power driven complex
SpaceMeta createPower(string id, size_t amount, string[string] params) {
    import std.conv, std.uuid;

    auto sm = new SpaceMeta;
    sm.id = id;

    for(size_t i = 0; i < amount; i++) {
        auto em = new EntityMeta;
        auto c = new Actuality;
        c.power = 1000;
        em.ptr = new EntityPtr;
        em.ptr.id = i.to!string;
        em.ptr.space = id;
        em.access = EntityAccess.Local;

        for(size_t j = 0; j < amount; j++) {
            if(i != j) {
                auto r = new Relation;
                r.entity = new EntityPtr;
                r.entity.id = j.to!string;
                r.entity.space = id;
                r.power = "init" in params ? params["init"].to!double : amount.to!double;
                c.relations ~= r;
            }
        }
        em.context = c;

        auto rr = new Receptor;
        rr.signal = "flow.complex.power.Act";
        rr.tick = "flow.complex.power.React";
        em.receptors ~= rr;

        auto dt = em.createTickMeta("flow.complex.power.Do");
        auto d = new DoData;
        d.req = c.power/amount;
        d.rest = d.req;
        dt.data = d;
        em.ticks ~= dt;

        sm.entities ~= em;
    }

    return sm;
}