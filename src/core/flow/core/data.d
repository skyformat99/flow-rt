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

class ProcessInfo : flow.data.engine.Data {
    mixin flow.data.engine.data;

    /// public RSA certificate (set by process from ProcessConfig)
    mixin flow.data.engine.array!(ubyte, "cert");

    /// process domain (top level domain of spaces in process)
    mixin flow.data.engine.array!(string, "domain");

    /// witnesses used to approve peers (no witnesses leads to general accepteance of peer processes)
    mixin flow.data.engine.array!(Witness, "witnesses");
}

/// configuration object of a process
class ProcessConfig : flow.data.engine.Data {
    mixin flow.data.engine.data;

    /// private/public RSA key (no key disables encryption)
    mixin flow.data.engine.array!(ubyte, "key");

    mixin flow.data.engine.field!(ProcessInfo, "info");

    /// junctions allow signals to get shipped across processes
    mixin flow.data.engine.array!(JunctionMeta, "junctions");
}

class SpaceMeta : flow.data.engine.Data {
    mixin flow.data.engine.data;

    /// identifier of the space
    mixin flow.data.engine.field!(string, "id");

    /// is space exposed to junctions?
    mixin flow.data.engine.field!(bool, "exposed");
    
    /// amount of worker threads for executing ticks
    mixin flow.data.engine.field!(size_t, "worker");

    /// entities of space
    mixin flow.data.engine.array!(EntityMeta, "entities");
}

class EntityMeta : flow.data.engine.Data {
    private import flow.data.engine : Data;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EntityPtr, "ptr");
    mixin flow.data.engine.field!(EntityAccess, "access");
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

/// scopes an entity can have
enum EntityAccess {
    Local,
    Global
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

class JunctionInfo : flow.data.data.IdData {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(ProcessInfo, "process");
    mixin flow.data.engine.field!(bool, "acceptsAnycast");
    mixin flow.data.engine.field!(bool, "acceptsMulticast");
}

abstract class ConnectorConfig : flow.data.engine.Data {
    mixin flow.data.engine.data;
    
    mixin flow.data.engine.field!(string, "type");
}

class JunctionMeta : flow.data.engine.Data {
    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(JunctionInfo, "info");
    mixin flow.data.engine.field!(ConnectorConfig, "connector");
}