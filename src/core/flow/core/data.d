module flow.core.data;

private import flow.data.engine;
private import flow.data.data;

/// data representing a signal
abstract class Signal : IdData {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "group");
    mixin field!(EntityPtr, "src");
}

/// data representing an unicast
class Unicast : Signal {
    mixin data;

    mixin field!(EntityPtr, "dst");
}

/// data representing a anycast
class Anycast : Signal {
    mixin data;

    mixin field!(string, "dst");
}

/// data representing a multicast
class Multicast : Signal {
    mixin data;

    mixin field!(string, "dst");
}

/*class Damage : Data {
    private import flow.data.engine : Data;

    mixin data;

    mixin field!(string, "msg");
    mixin field!(Data, "recovery");
}*/

/// metadata of a space
class SpaceMeta : Data {
    mixin data;

    /// identifier of the space
    mixin field!(string, "id");
    
    /// amount of worker threads for executing ticks
    mixin field!(size_t, "worker");

    /// junctions allow signals to get shipped across spaces
    mixin array!(JunctionMeta, "junctions");

    /// entities of space
    mixin array!(EntityMeta, "entities");
}

/// info of a junction
class JunctionInfo : IdData {
    mixin data;

    mixin field!(string, "space");

    /// public RSA certificate (set by junction itself from private key)
    mixin array!(ubyte, "cert");

    mixin field!(bool, "isConfirming");

    mixin field!(bool, "acceptsAnycast");
    mixin field!(bool, "acceptsMulticast");
}

/// metadata of a junction
class JunctionMeta : Data {
    mixin data;

    mixin field!(JunctionInfo, "info");
    mixin field!(string, "type");
    mixin field!(ushort, "level");

    /// witnesses used to approve peers (no witnesses leads to general accepteance of peer certificates)
    mixin array!(Witness, "witnesses");

    /// private/public RSA key (no key disables encryption)
    mixin array!(ubyte, "key");
}

/// metadata of an entity
class EntityMeta : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(Data, "context");
    mixin field!(ushort, "level");
    mixin array!(Event, "events");
    mixin array!(Receptor, "receptors");

    mixin array!(TickMeta, "ticks");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "space");
}

/// type of events can occur in an entity
enum EventType {
    OnCreated,
    OnTicking,
    OnFrozen,
    OnDisposed
}

/// mapping a tick to an event
class Event : Data {
    mixin data;

    mixin field!(EventType, "type");
    mixin field!(string, "tick");
}

/// metadata of a tick
public class TickMeta : Data {
    mixin data;

    mixin field!(TickInfo, "info");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(Data, "data");
}

/// info of a tick
class TickInfo : IdData {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

/// mapping a tick to a signal
class Receptor : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
}

/// root certificate
class Witness : Data {
    mixin data;

    /// name of the witness
    mixin field!(string, "name");

    /// certificate of the witness
    mixin array!(ubyte, "cert");
}