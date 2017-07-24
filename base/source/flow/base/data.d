module flow.base.data;

import __flow.data, __flow.signal;

import std.uuid;

/// identifyable data
class IdData : Data {
    mixin data;

    mixin field!(UUID, "id");
}

/// configuration object of flow process
class FlowConfig : Data {
    mixin data;
    
    mixin field!(FlowPtr, "ptr");
    mixin field!(bool, "tracing");
    mixin field!(size_t, "worker");
    mixin field!(bool, "isolateMem");
    mixin field!(bool, "preventIdTheft");
}

/// referencing a specific process having an unique ptress like udp://hostname:port
class FlowPtr : Data {
    mixin data;

    mixin field!(string, "address");
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
    mixin field!(UUID, "trigger");
    mixin field!(Signal, "signal");
    mixin field!(TickMeta, "previous");
    mixin field!(Data, "data");
}

/// scopes an entity can have
enum EntitySpace {
    Local,
    Global
}

class ListeningMeta : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "type");
    mixin field!(string, "domain");
}

class EntityConfig : Data {
    mixin data;

    mixin field!(bool, "quiet");
}

/// referencing a specific entity 
class EntityInfo : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(EntitySpace, "space");
    mixin field!(EntityConfig, "config");

    mixin array!(string, "signals");
}

class EntityMetaDamage : Data {
    mixin data;

    mixin field!(string, "msg");
    mixin field!(Data, "recovery");
}

class EntityMeta : Data {
    mixin data;

    mixin array!(EntityMetaDamage, "damages");

    mixin field!(EntityInfo, "info");
    mixin array!(EntityMeta, "children");
    mixin field!(Data, "context");
    mixin array!(ListeningMeta, "listenings");
    mixin array!(Signal, "inbound");
    mixin array!(TickMeta, "ticks");
}

class Signal : IdData {
    mixin signal;

    mixin field!(UUID, "group");
    mixin field!(bool, "traceable");
    mixin field!(string, "type");
    mixin field!(EntityPtr, "source");
}

class Unicast : Signal {
    mixin signal;

    mixin field!(EntityPtr, "destination");
}

class Multicast : Signal {
    mixin signal;

    mixin field!(string, "domain");
}

class Anycast : Signal {    
    mixin signal;

    mixin field!(string, "domain");
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