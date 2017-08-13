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
    mixin signal;

    mixin field!(double, "power");
}

/// initializes a power driven entity
class OnTick : Tick {
    override void run() {
        // on startup we calculate the power of actuality for each entity
        auto c = this.context.as!Actuality;

        c.power = 0.0;
        foreach(r; c.relations)
            c.power += r.power;
    }
}

/// reaction of a power driven entity on an act of power
class React : Tick {    
    override void run() {
        import std.math, std.range, std.algorithm.mutation;

        auto s = this.trigger.as!Act;
        auto c = this.context.as!Actuality;

        auto req = s.power;

        synchronized(this.sync.writer) {
            /* requested power is dragged from all other relations,
            this would be a task for a quantum computer I assume */
            auto rest = s.power;
            while(!rest.isIdentical(0.0)) {
                c.power = 0.0; // we recalculate actuality power
                auto share = rest/c.relations.length-1;
                foreach(i, r; c.relations.enumerate.retro) {
                    if(s.src != r.entity) {
                        if(r.power <= share) {
                            rest -= share - r.power;
                            c.relations.remove(i);
                        } else {
                            rest -= share;
                            r.power -= share;
                            c.power += r.power;
                        }
                    }
                }
            }
        }
    }
}

/// what an entity is doing as long as it exists
class Exist : Tick {
    /// ticks equals costs is the amount of relations
    override @property size_t costs() {
        return this.context.as!Actuality.relations.length;
    }

    override void run() {
        import std.math;

        auto c = this.context.as!Actuality;

        synchronized(this.sync.writer) {
            // I request from each relation the adequate share of the own actuality
            foreach(i, r; c.relations) {
                auto addition = r.power/c.power;
                auto s = new Act;
                s.power = addition;
                if(this.send(s, r.entity)) {
                    r.power += addition;

                    // since we avoid recalculating power of own actuality again and again, we track changes
                    c.power += addition;
                }
            }
        }

        this.next(this.info.type);
    }
}

/// creates a power driven complex
SpaceMeta createPower(string id, size_t amount, string[string] params) {
    import flow.base.util;

    import std.conv, std.uuid;

    auto sm = new SpaceMeta;
    sm.id = id;

    for(size_t i = 0; i < amount; i++) {
        auto em = new EntityMeta;
        auto c = new Actuality;
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

        auto ote = new Event;
        ote.type = EventType.OnTick;
        ote.tick = "flow.complex.power.OnTick";
        em.events ~= ote;

        auto rr = new Receptor;
        rr.signal = "flow.complex.power.Act";
        rr.tick = "flow.complex.power.React";
        em.receptors ~= rr;

        auto etm = new TickMeta;
        etm.info = new TickInfo;
        etm.info.entity = em.ptr;
        etm.info.type = "flow.complex.power.Exist";
        etm.info.group = randomUUID;
        em.ticks ~= etm;

        sm.entities ~= em;
    }

    return sm;
}