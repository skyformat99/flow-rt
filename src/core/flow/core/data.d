module flow.core.data;

private static import flow.data.engine;
private static import flow.data.data;

abstract class Signal : flow.data.data.IdData {
    private import std.uuid : UUID;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(UUID, "group");
    mixin flow.data.engine.field!(EntityPtr, "src");
}

class Unicast : Signal {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EntityPtr, "dst");
}

class Multicast : Signal {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "space");
}

class Anycast : Signal {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "space");
}

/*class Damage : flow.data.engine.Data {
    private import flow.data.engine : Data;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "msg");
    mixin flow.data.engine.field!(Data, "recovery");
}*/

class SpaceMeta : flow.data.engine.Data {
    mixin flow.data.engine.data;

    /// identifier of the space
    mixin flow.data.engine.field!(string, "id");

    /// is space exposed to junctions?
    mixin flow.data.engine.field!(bool, "exposed");
    
    /// amount of worker threads for executing ticks
    mixin flow.data.engine.field!(size_t, "worker");

    /// junctions allow signals to get shipped across spaces
    mixin flow.data.engine.array!(JunctionMeta, "junctions");

    /// entities of space
    mixin flow.data.engine.array!(EntityMeta, "entities");
}

class JunctionInfo : flow.data.data.IdData {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "space");

    /// public RSA certificate (set by junction itself from private key)
    mixin flow.data.engine.array!(ubyte, "cert");

    mixin flow.data.engine.field!(bool, "isConfirming");

    mixin flow.data.engine.field!(bool, "acceptsAnycast");
    mixin flow.data.engine.field!(bool, "acceptsMulticast");
}

class JunctionMeta : flow.data.engine.Data {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(JunctionInfo, "info");
    mixin flow.data.engine.field!(string, "type");
    mixin flow.data.engine.field!(ushort, "level");

    /// witnesses used to approve peers (no witnesses leads to general accepteance of peer certificates)
    mixin flow.data.engine.array!(Witness, "witnesses");

    /// private/public RSA key (no key disables encryption)
    mixin flow.data.engine.array!(ubyte, "key");
}

class EntityMeta : flow.data.engine.Data {
    private import flow.data.engine : Data;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EntityPtr, "ptr");
    mixin flow.data.engine.field!(ushort, "level");
    mixin flow.data.engine.field!(Data, "context");
    mixin flow.data.engine.array!(Event, "events");
    mixin flow.data.engine.array!(Receptor, "receptors");

    mixin flow.data.engine.array!(TickMeta, "ticks");
}

/// referencing a specific entity 
class EntityPtr : flow.data.engine.Data {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "id");
    mixin flow.data.engine.field!(string, "space");
}

enum EventType {
    OnCreated,
    OnTicking,
    OnFrozen,
    OnDisposed
}

class Event : flow.data.engine.Data {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EventType, "type");
    mixin flow.data.engine.field!(string, "tick");
}

public class TickMeta : flow.data.engine.Data {
    private import flow.data.engine : Data;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(TickInfo, "info");
    mixin flow.data.engine.field!(Signal, "trigger");
    mixin flow.data.engine.field!(TickInfo, "previous");
    mixin flow.data.engine.field!(Data, "data");
}

class TickInfo : flow.data.data.IdData {
    private import std.uuid : UUID;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EntityPtr, "entity");
    mixin flow.data.engine.field!(string, "type");
    mixin flow.data.engine.field!(UUID, "group");
}

class Receptor : flow.data.engine.Data {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(string, "signal");
    mixin flow.data.engine.field!(string, "tick");
}

class Witness : flow.data.engine.Data {
    mixin flow.data.engine.data;

    /// name of the witness
    mixin flow.data.engine.field!(string, "name");

    /// certificate of the witness
    mixin flow.data.engine.array!(ubyte, "cert");
}