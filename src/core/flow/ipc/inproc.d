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
    private static shared InProcessJunction[][UUID] junctions;

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
            junctions[this.id] ~= this.as!(shared(InProcessJunction));
    }

    override void down() {
        import flow.util.templates;
        import std.algorithm;

        synchronized(lock.writer)
            foreach(i, j; junctions[this.id].dup)
                if(j.as!InProcessJunction == this)
                    junctions[this.id].remove(i);
    }

    override bool ship(Unicast s) {
        return false;
    }

    override bool ship(T)(T s) if(is(T:Anycast) || is(T:Multicast)) {
        return false;
    }
}