module flow.ipc.inproc;

static import flow.core.data;
static import flow.core.engine;

class InProcessJunctionMeta : flow.core.data.JunctionMeta {
    private import std.uuid : UUID;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(UUID, "id");
}

class InProcessJunction : flow.core.engine.Junction {
    private import core.sync.rwmutex;
    private import flow.core.data;
    private import std.uuid;

    private static __gshared ReadWriteMutex lock;
    private static shared InProcessJunction[string][UUID] junctions;

    @property UUID id() {
        import flow.util.templates;
        return this.meta.as!InProcessJunctionMeta.id;
    }

    shared static this() {
        lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    this() {
        super();
    }

    override void up() {
        import flow.util.templates;

        synchronized(lock.writer)
            junctions[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));
    }

    override void down() {
        import flow.util.templates;

        synchronized(lock.writer)
            junctions[this.id].remove(this.meta.info.space);
    }

    override bool ship(Unicast s) {
        import flow.util.templates;

        synchronized(lock.reader)
            if(s.dst.space != this.meta.info.space && s.dst.space in junctions[this.id])
                return junctions[this.id][s.dst.space].as!InProcessJunction.deliver(s);
        
        return false;
    }

    override bool ship(Anycast s) {
        import flow.util.templates;

        auto cw = containsWildcard(s.dst);

        synchronized(lock.reader)
            if(cw)
                foreach(j; junctions[this.id])
                    if(j.as!InProcessJunction.deliver(s))
                        return true;
            else
                if(s.dst != this.meta.info.space && s.dst in junctions[this.id])
                    return junctions[this.id][s.dst].as!InProcessJunction.deliver(s);
                    
        return false;
    }

    override bool ship(Multicast s) {
        import flow.util.templates;

        auto cw = containsWildcard(s.dst);

        auto ret = false;
        synchronized(lock.reader)
            if(cw)
                foreach(j; junctions[this.id])
                    ret = j.as!InProcessJunction.deliver(s) || ret;
            else
                if(s.dst != this.meta.info.space && s.dst in junctions[this.id])
                    ret = junctions[this.id][s.dst].as!InProcessJunction.deliver(s);
                    
        return ret;
    }
}

private bool containsWildcard(string dst) {
    import std.algorithm.searching;

    return dst.any!(a => a = '*');
}

version(unittest) {
    
}

unittest {

}