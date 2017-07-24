module flow.base.data;

import __flow.data, __flow.signal;

import std.uuid;

/// identifyable data
class IdData : Data {
    mixin database;

    mixin field!(UUID, "id");
}

/// configuration object of a process
class ProcessConfig : Data {
    mixin database;

    mixin field!(size_t, "worker");
}

/// referencing a specific flow having an unique ptress like udp://hostname:port/flow
class FlowPtr : Data {
    mixin database;

    mixin field!(string, "id");
}

class TickInfo : IdData {
    mixin database;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

class TickMeta : Data {
    mixin database;

    mixin field!(TickInfo, "info");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(Data, "data");
}

/// scopes an entity can have
enum EntitySpace {
    Local,
    Global
}

class ListeningMeta : Data {
    mixin database;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin database;

    mixin field!(string, "id");
    mixin field!(string, "type");
    mixin field!(FlowPtr, "flow");
}

class EntityConfig : Data {
    mixin database;

    mixin field!(bool, "quiet");
}

/// referencing a specific entity 
class EntityInfo : Data {
    mixin database;

    mixin field!(EntityPtr, "ptr");
    mixin field!(EntitySpace, "space");
    mixin field!(EntityConfig, "config");

    mixin array!(string, "signals");
}

class EntityMetaDamage : Data {
    mixin database;

    mixin field!(string, "msg");
    mixin field!(Data, "recovery");
}

class EntityMeta : Data {
    mixin database;

    mixin array!(EntityMetaDamage, "damages");

    mixin field!(EntityInfo, "info");
    mixin array!(EntityMeta, "children");
    mixin field!(Data, "context");
    mixin array!(ListeningMeta, "listenings");
    mixin array!(Signal, "inbound");
    mixin array!(TickMeta, "ticks");
}

class Signal : IdData {
    mixin signalbase;

    mixin field!(UUID, "group");
    mixin field!(bool, "traceable");
    mixin field!(string, "type");
    mixin field!(EntityPtr, "source");
}

class Unicast : Signal {
    mixin signalbase;

    mixin field!(EntityPtr, "destination");
}

class Multicast : Signal {
    mixin signalbase;

    mixin field!(string, "flow");
}

class Anycast : Signal {    
    mixin signalbase;

    mixin field!(string, "flow");
}

class Ping : Multicast {
    mixin signalbase;
}

class UPing : Unicast {
    mixin signalbase;
}

class Pong : Unicast {
    mixin signalbase;

    mixin field!(EntityPtr, "ptr");
    mixin array!(string, "signals");
}

class WrappedSignal : Unicast {
    mixin signalbase!(Signal);
}