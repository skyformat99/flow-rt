module flow.complex.power_old;

import flow.data, flow.util, flow.core;

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
    mixin field!(Relation[], "relations");
}

/// signals an act of power
class Act : Unicast {
    mixin data;

    mixin field!(double, "power");
}

/// reaction of a power driven entity on an act of power
class React : Tick {
    override @property bool accept() {
        import std.math, std.array, std.conv, std.algorithm.sorting, std.algorithm.iteration;

        auto s = this.trigger.as!Act;
        auto c = this.context.as!Actuality;

        debug(tick) this.msg(LL.Debug, "React::accept: before sync");
        // we only accept it, if its power is enough to make a difference
        synchronized(this.sync.writer) {
            auto newPower = c.power - s.power;
            if(!c.power.isIdentical(newPower)) {
                debug(tick) this.msg(LL.Debug, "React::accept: !isIdentical");
                // if it makes a difference, we give this piece of power to requester
                debug(tick) this.msg(LL.Debug, "React::accept: c.power="~newPower.to!string);
                c.power = newPower;
                debug(tick) this.msg(LL.Debug, "React::accept: c.power'="~newPower.to!string);

                debug(tick) this.msg(LL.Debug, "React::accept: c.realtions.length="~c.relations.length.to!string);
                // we increase the virtual power of requester
                auto rs = c.relations.filter!(a=>a.entity == s.src);
                Relation r;
                if(rs.empty) { // if we do not have a relation we create a new one
                    debug(tick) this.msg(LL.Debug, "React::accept: rs.empty");
                    r = new Relation;
                    r.entity = s.src;
                    c.relations ~= r;
                    debug(tick) this.msg(LL.Debug, "React::accept: c.realtions.length'="~c.relations.length.to!string);
                } else {
                    r = rs.front;
                    debug(tick) this.msg(LL.Debug, "React::accept: !rs.empty");
                }
                debug(tick) this.msg(LL.Debug, "React::accept: r.power="~r.power.to!string);
                r.power += s.power;
                debug(tick) this.msg(LL.Debug, "React::accept: r.power'="~r.power.to!string);

                debug(tick) this.msg(LL.Debug, "React::accept: done");
                return true;
            } else {
                debug(tick) this.msg(LL.Debug, "React::accept: cannot do");
                debug(tick) this.msg(LL.Debug, "React::accept: done");
                return false;
            }
        }
    }
}

class Exist : Tick {
    override void run() {
        import core.thread;
        import std.math, std.random, std.conv, std.algorithm.mutation, std.range.primitives;

        auto c = this.context.as!Actuality;
        auto sleep = false;

        debug(tick) this.msg(LL.Debug, "Exist::run: before sync");
        synchronized(this.sync.writer) {
            sleep = c.relations.empty;
            debug(tick) this.msg(LL.Debug, "Exist::run: c.realtions.length'="~c.relations.length.to!string);
            if(!sleep) { // if there are no relations there is nothing to do than wait a bit and check again
                debug(tick) this.msg(LL.Debug, "Exist::run: can do");

                auto rnd = uniform(0, c.relations.length);
                debug(tick) this.msg(LL.Debug, "Exist::run: rnd="~rnd.to!string);
                auto r = c.relations[rnd];
                debug(tick) this.msg(LL.Debug, "Exist::run: r.power="~r.power.to!string);
                auto req = r.power/c.power;
                auto newPower = c.power += req;
                // creating new act
                auto act = new Act;
                act.power = req;
                debug(tick) this.msg(LL.Debug, "Exist::run: req="~req.to!string);
                // if target can deliver power from own pov and its pov
                if(!c.power.isIdentical(newPower) && req <= r.power && this.send(act, r.entity)) {
                    debug(tick) this.msg(LL.Debug, "Exist::run: !isIdentical && accepted");

                    debug(tick) this.msg(LL.Debug, "Exist::run: c.power="~c.power.to!string);
                    c.power += req;
                    debug(tick) this.msg(LL.Debug, "Exist::run: c.power'="~c.power.to!string);
                    // if from own pov there is power left just decrease
                    debug(tick) this.msg(LL.Debug, "Exist::run: r.power="~r.power.to!string);
                    if(req < r.power) {
                        r.power -= req;
                        debug(tick) this.msg(LL.Debug, "Exist::run: r.power'="~r.power.to!string);
                    } else {// if not, relation is delpleted and removed
                        c.relations.remove(rnd);
                        debug(tick) this.msg(LL.Debug, "Exist::run: r removed");
                    }
                }
            } else {
                debug(tick) this.msg(LL.Debug, "Exist::run: cannot do");
            }
        }

        if(sleep) {
            debug(tick) this.msg(LL.Debug, "Exist::run: sleeping");
            Thread.sleep(5.msecs);
        }
        else
            debug(tick) this.msg(LL.Debug, "Exist::run: not sleeping");

        debug(tick) this.msg(LL.Debug, "Exist::run: next");
        this.next(this.info.type);
        debug(tick) this.msg(LL.Debug, "Exist::run: done");
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
        c.power = "init" in params ? params["init"].to!double : 1000.0;
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
                r.power = ("init" in params ? params["init"].to!double : 1000.0)/amount;
                c.relations ~= r;
            }
        }
        em.context = c;

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