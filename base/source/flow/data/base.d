module flow.data.base;

import flow.base.data;

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

/// configuration object of a process
class ProcessConfig : Data {
    mixin data;

    mixin field!(size_t, "worker");
    mixin field!(string, "address");
    mixin field!(bool, "hark");
}

class SpacePtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "process");
}

class SpaceMeta : Data {
    mixin data;

    mixin field!(SpacePtr, "ptr");
    mixin array!(EntityMeta, "entities");
}

class TickPtr : IdData {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

class TickMeta : Data {
    mixin data;

    mixin field!(TickPtr, "ptr");
    mixin field!(Signal, "trigger");
    mixin field!(TickPtr, "previous");
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
    mixin field!(string, "process");
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