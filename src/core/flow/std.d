module flow.std;

import flow.core.data;

import core.time;
import std.uuid, std.socket;

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

enum SocketRole {
    Master,
    Slave
}

class SocketMeta : Data {
    mixin data;

    /// address familiy (see std.socket)
    mixin field!(AddressFamily, "family");

    /// socket type (see std.socket)
    mixin field!(SocketType, "type");

    /// listening (master) or connecting (slave)
    mixin field!(SocketRole, "role");

    /// address of listener
    mixin field!(string, "addr");
}

class NetMeta : Data {
    mixin data;

    /// stores runtime informations about spaces available for shifting via this net
    string[] spaces;

    /// socket information
    mixin field!(SocketMeta, "socket");
    
    /// own private key
    mixin array!(ubyte, "ownCert");

    /// public key of the peer or empty for authority validation
    mixin array!(ubyte, "peerCert");
}

class Authority : Data {
    mixin data;

    /// name of the authority
    mixin field!(string, "name");

    /// certificate of the authority
    mixin array!(ubyte, "cert");
}

/// configuration object of a process
class ProcessConfig : Data {
    mixin data;

    /// amount of worker threads for executing ticks
    mixin field!(size_t, "worker");

    /// is process harking to space wildcards?
    mixin field!(bool, "hark");

    /// authorities used to validate peers
    mixin array!(Authority, "authorities");
    mixin array!(NetMeta, "nets");
}

class TickInfo : IdData {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

/// scopes an entity can have
enum EntityAccess {
    Local,
    Global
}

class Receptor : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
}

enum EventType {
    OnCreated,
    OnTicking,
    OnFrozen,
    OnDisposed
}

class Event : Data {
    mixin data;

    mixin field!(EventType, "type");
    mixin field!(string, "tick");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin data;

    mixin field!(string, "id");
    mixin field!(string, "space");
}

class Signal : IdData {
    mixin data;

    mixin field!(UUID, "group");
    mixin field!(EntityPtr, "src");
}

class Unicast : Signal {
    mixin data;

    mixin field!(EntityPtr, "dst");
}

class Multicast : Signal {
    mixin data;

    mixin field!(string, "space");
}

class Anycast : Signal {
    mixin data;

    mixin field!(string, "space");
}

class Ping : Multicast {
    mixin data;
}

class UPing : Unicast {
    mixin data;
}

class Pong : Unicast {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin array!(string, "signals");
}

class WrappedSignal : Unicast {
    mixin data;

    mixin field!(Signal, "signal");
}