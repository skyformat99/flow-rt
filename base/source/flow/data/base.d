module flow.data.base;

import flow.base.data;

import core.time;
import std.uuid;

/// identifyable data
class IdData : Data {
    mixin data;

    mixin field!(UUID, "id");
}

class Damage : Data {
    mixin data;

    mixin field!(string, "msg");
    mixin field!(Data, "recovery");
}

class NetMeta : Data {
    mixin data;

    /// listener should listen to
    mixin field!(string, "addr");
}

/** central nets are relying on a
space lookup service to find certain spaces */
class CentralNetMeta : NetMeta {
    mixin data;

    mixin array!(string, "lookups");
}

/** decentral nets are creating a cluod graph of
related nodes to examine optimal routes to certain spaces */
class DecentralNetMeta : NetMeta {
    mixin data;
    
    mixin array!(NodeInfo, "nodes");
}

class NodeInfo : Data {
    mixin data;

    mixin field!(string, "addr");
    
    // TODO local part of cloud graph
}

/// configuration object of a process
class ProcessConfig : Data {
    mixin data;

    mixin field!(size_t, "worker");
    mixin field!(bool, "hark");
    mixin array!(NetMeta, "nets");
}

class SpaceMeta : Data {
    mixin data;

    mixin field!(string, "id");
    mixin array!(EntityMeta, "entities");
}

class TickInfo : IdData {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

class TickMeta : Data {
    mixin data;

    mixin field!(TickInfo, "info");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(Data, "data");
}

/// scopes an entity can have
enum Access {
    Local,
    Global
}

class Receptor : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "space");
    mixin field!(Access, "access");
}

class EntityMeta : Data {
    mixin data;

    mixin array!(Damage, "damages");

    mixin field!(EntityPtr, "ptr");
    mixin field!(Data, "context");
    mixin array!(Receptor, "receptors");
    mixin array!(Signal, "inbound");
    mixin array!(TickMeta, "ticks");
}

class Signal : IdData {
    mixin signal;

    mixin field!(UUID, "group");
    mixin field!(EntityPtr, "src");
}

class Unicast : Signal {
    mixin signal;

    mixin field!(EntityPtr, "dst");
}

class Multicast : Signal {
    mixin signal;

    mixin field!(string, "space");
}

class Ping : Multicast {
    mixin signal;
}

class UPing : Unicast {
    mixin signal;
}

class Pong : Unicast {
    mixin signal;

    mixin field!(EntityPtr, "ptr");
    mixin array!(string, "signals");
}

class WrappedSignal : Unicast {
    mixin signal!(Signal);
}