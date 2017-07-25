module flow.base.data;

import __flow.data, __flow.signal;

import std.uuid;

/// identifyable data
class IdData : Data {
    mixin data;

    mixin field!(UUID, "id");
}

/// configuration object of a process
class ProcessConfig : Data {
    mixin data;

    mixin field!(size_t, "worker");
}

/// referencing a specific flow having an unique ptress like udp://hostname:port/flow
class FlowPtr : Data {
    mixin data;

    mixin field!(string, "id");
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
    mixin field!(string, "type");
    mixin field!(FlowPtr, "flow");
}

class EntityConfig : Data {
    mixin data;

    mixin field!(bool, "quiet");
}

/// referencing a specific entity 
class EntityInfo : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(Access, "space");
    mixin field!(EntityConfig, "config");

    mixin array!(string, "signals");
}

class Damage : Data {
    mixin data;

    mixin field!(string, "msg");
    mixin field!(Data, "recovery");
}

class EntityMeta : Data {
    mixin data;

    mixin array!(Damage, "damages");

    mixin field!(EntityInfo, "info");
    mixin field!(Data, "context");
    mixin array!(Receptor, "listenings");
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

    mixin field!(string, "flow");
}

class Anycast : Signal {    
    mixin signal;

    mixin field!(string, "flow");
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