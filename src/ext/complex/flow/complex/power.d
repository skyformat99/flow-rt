module flow.complex.power;

import flow.core.data, flow.core.util, flow.core;

/// describes a powerdriven relation
class Relation : Data {
    mixin data;

    /// relation with
    mixin field!(EntityPtr, "entity");

    /// relation power
    mixin field!(size_t, "power");
}

/// describes the actuality of a power driven entity
class Actuality : Data {
    mixin data;

    /** inner power
    (sum of relation powers and inner power
    has to be in balance for existance) */
    mixin field!(size_t, "power");

    /// relations of entity
    mixin field!(Relation[], "relations");
}

/// signals an act of power
class Act : Unicast {
    mixin data;

    /// power of act
    mixin field!(size_t, "power");
}

/// reaction of a power driven entity on an act of power
class React : Tick {
    override @property bool accept() {
        import std.math, std.conv, std.array;
        import std.algorithm.mutation, std.algorithm.sorting, std.algorithm.iteration;

        auto s = this.trigger.as!Act;
        auto c = this.context!Actuality;
        
        debug(tick) this.msg(LL.Debug, "React::accept: s.power="~s.power.to!string);
        debug(tick) this.msg(LL.Debug, "React::accept: before sync");
        synchronized(this.sync) {
            if(!c.relations.empty && c.power > s.power) { // it can only give power if it has this power
                // can the act cut out others so it is consumed completely?
                auto canAccept = false;
                Relation found;
                size_t[] cut;
                auto rest = s.power;
                foreach(i, r; c.relations) {
                    if(r.entity != s.src) { // an entity cannot cut out its own relation
                        if(rest > r.power) {
                            r.power = 0;
                            cut ~= i;
                            rest -= r.power;
                        }
                        else if(rest == r.power) {
                            r.power = 0;
                            cut ~= i;
                            rest = 0;
                            canAccept = true;
                        } else break;
                    } else found = r;
                }

                if(canAccept) {
                    debug(tick) this.msg(LL.Debug, "React::accept: can accept");
                    // remove cut out relations and add power of oct to own power
                    foreach_reverse(i; cut) {
                        debug(tick) this.msg(LL.Debug, c.relations[i], "React::accept: removing relation");
                        c.relations = c.relations.remove(i).array;
                    }

                    // if relation to src is not existing, create it
                    if(found is null) {
                        debug(tick) this.msg(LL.Debug, "React::accept: src relation not found, creating");
                        auto r = new Relation;
                        r.entity = s.src;
                        r.power = s.power;
                        c.relations ~= r;
                        found = r;
                    } else {
                        debug(tick) this.msg(LL.Debug, found, "React::accept: src relation found");
                    }

                    // now relation with src is strengthened by power amount
                    debug(tick) this.msg(LL.Debug, "React::accept: found.power="~found.power.to!string);
                    found.power += s.power;
                    debug(tick) this.msg(LL.Debug, "React::accept: found.power'="~found.power.to!string);

                    // on the other hand actuality is loosing own power
                    debug(tick) this.msg(LL.Debug, "React::accept: c.power="~c.power.to!string);
                    c.power -= s.power;
                    debug(tick) this.msg(LL.Debug, "React::accept: c.power'="~c.power.to!string);

                    // finally relations are sorted ascending
                    debug(tick) this.msg(LL.Debug, "React::accept: sorting");
                    c.relations = c.relations.sort!((a, b) => a.power < b.power).array; // << PROBLEM

                    return true;
                } else {
                    debug(tick) this.msg(LL.Debug, "React::accept: can't accept");
                    return false;
                }
            } else {
                debug(tick) this.msg(LL.Debug, "React::accept: don't have required power");
                return false;
            }
        }
    }
}

class Exist : Tick {
    override void run() {
        import core.thread;
        import std.math, std.conv, std.range.primitives, std.algorithm.iteration;

        auto c = this.context!Actuality;

        debug(tick) this.msg(LL.Debug, "Exist::run: before sync");
        Relation[] relations;
        synchronized(this.sync.reader)
            relations = c.relations.dup;
        if(!relations.empty) { // this whole things only makes sense if there are relations
            debug(tick) this.msg(LL.Debug, "Exist::run: !c.relations.empty");
            // does the actuality has less power than its relations?
            size_t miss;
            synchronized(this.sync.reader)
                miss = relations.map!(a => a.power).reduce!((a, b) => a + b) - c.power;
            debug(tick) this.msg(LL.Debug, "Exist::run: miss="~miss.to!string);

            // gets what it can for getting back to balance
            if(miss > 0) {
                foreach_reverse(i, r; relations) {
                    size_t rpower;
                    synchronized(this.sync.reader)
                        rpower = r.power;

                    if(rpower >= miss) {
                        auto a = new Act;
                        a.power = miss;
                        if(this.send(a, r.entity)) {
                            synchronized(this.sync)
                                c.power += miss;
                            break;
                        }
                    } else {
                        auto a = new Act;
                        a.power = rpower;
                        if(this.send(a, r.entity)) {
                            synchronized(this.sync)
                                c.power += rpower;
                            miss -= rpower;
                            if(miss < 1) {
                                break;
                            }
                        }
                    }
                }
            }
        }
        
        debug(tick) this.msg(LL.Debug, "Exist::run: next");
        this.next(fqn!(typeof(this)));
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
        c.power = amount;
        em.ptr = new EntityPtr;
        em.ptr.id = i.to!string;
        em.ptr.space = id;
        em.level = 0;

        for(size_t j = 0; j < amount; j++) {
            if(i != j) {
                auto r = new Relation;
                r.entity = new EntityPtr;
                r.entity.id = j.to!string;
                r.entity.space = id;
                r.power = 1;
                c.relations ~= r;
            }
        }
        em.context ~= c;

        auto rr = new Receptor;
        rr.signal = "flow.complex.power.Act";
        rr.tick = "flow.complex.power.React";
        em.receptors ~= rr;

        auto dt = em.addTick("flow.complex.power.Exist");
        em.ticks ~= dt;

        sm.entities ~= em;
    }

    return sm;
}