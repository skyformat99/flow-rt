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
class Act : Anycast {
    mixin data;

    mixin field!(double, "power");
}

/// reaction of a power driven entity on an act of power
class React : Tick {    
    override void run() {
        import std.math, std.algorithm.mutation, std.algorithm.searching;

        auto s = this.trigger.as!Act;
        auto c = this.context.as!Actuality;

        synchronized(this.sync.writer) {
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
        ote.type = EventType.OnCreated;
        ote.tick = "flow.complex.power.OnCreated";
        em.events ~= ote;

        auto rr = new Receptor;
        rr.signal = "flow.complex.power.Act";
        rr.tick = "flow.complex.power.React";
        em.receptors ~= rr;

        sm.entities ~= em;
    }

    return sm;
}