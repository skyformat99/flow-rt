module flow.ipc.inproc;

private import flow.data;
private import flow.core;

/// metadata of in process junction
class InProcessJunctionMeta : JunctionMeta {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "id");
}

/// junction allowing direct signalling between spaces hosted in same process
class InProcessJunction : Junction {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import std.uuid : UUID;

    private static __gshared ReadWriteMutex lock;
    private static shared InProcessJunction[string][UUID] junctions;

    /// instances with the same id belong to the same junction
    @property UUID id() {
        import flow.util : as;
        return this.meta.as!InProcessJunctionMeta.id;
    }

    shared static this() {
        lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    /// ctor
    this() {
        super();
    }

    override void up() {
        import flow.util : as;

        synchronized(lock.writer)
            junctions[this.id][this.meta.info.space] = this.as!(shared(InProcessJunction));
    }

    override void down() {
        synchronized(lock.writer)
            junctions[this.id].remove(this.meta.info.space);
    }

    override bool ship(Unicast s) {
        import flow.util : as;

        synchronized(lock.reader)
            if(s.dst.space != this.meta.info.space && s.dst.space in junctions[this.id])
                return junctions[this.id][s.dst.space].as!InProcessJunction.deliver(s);
        
        return false;
    }

    override bool ship(Anycast s) {
        import flow.util : as;

        auto cw = containsWildcard(s.dst);

        synchronized(lock.reader)
            if(cw) {
                foreach(j; junctions[this.id])
                    if(j.as!InProcessJunction.deliver(s))
                        return true;
            } else {
                if(s.dst != this.meta.info.space && s.dst in junctions[this.id])
                    return junctions[this.id][s.dst].as!InProcessJunction.deliver(s);
            }
                    
        return false;
    }

    override bool ship(Multicast s) {
        import flow.util : as;

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
    import std.algorithm.searching : any;

    return dst.any!(a => a = '*');
}

unittest {
    /*import flow.core;
    import flow.ipc.test;
    import std.uuid;

    auto proc = new Process;
    scope(exit) proc.destroy;

    auto spc1Domain = "spc1.test.inproc.ipc.flow";
    auto spc2Domain = "spc2.test.inproc.ipc.flow";

    auto spc1 = createSpace(spc1Domain);
    spc1.addEntity();
    spc1.addInProcJunction(randomUUID);

    auto spc2 = createSpace(spc2Domain);
    spc1.addEntity();
    spc1.addInProcJunction(randomUUID);

    proc.add(spc1);
    proc.add(spc2);*/
}