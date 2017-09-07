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

class JunctionInfo : IdData {
    mixin data;

    mixin field!(bool, "forward");
}

abstract class JunctionMeta : Data {
    mixin data;

    mixin field!(JunctionInfo, "info");
    mixin field!(ListenerMeta, "listener");

    mixin array!(PeerMeta, "peers");
}

class StaticJunctionMeta : JunctionMeta {
    mixin data;
}

//class DynamicJunctionMeta : JunctionMeta {
//    mixin data;
//}

abstract class ListenerInfo : Data {
    mixin data;

    mixin array!(ubyte, "cert");
}

class InetListenerInfo : Data {
    mixin data;

    mixin array!(ubyte, "ver");
    mixin array!(ubyte, "addr");
    mixin array!(ushort, "port");
}

abstract class ListenerMeta : Data {
    mixin data;

    mixin field!(ListenerInfo, "info");
}

class InetListenerMeta : ListenerMeta {
    mixin data;

    mixin field!(InetListenerInfo, "info");
}

class PeerMeta : Data {
    mixin data;

    /// forwarding signals coming from this peer to other peers?
    mixin field!(bool, "forward");
    
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

    /// authorities used to validate peers
    mixin array!(Authority, "authorities");
    mixin array!(JunctionMeta, "junctions");
}

class SpaceMeta : Data {
    mixin data;

    /// identifier of the space
    mixin field!(string, "id");

    /// is space harking to wildcard
    mixin field!(bool, "hark");
    
    /// amount of worker threads for executing ticks
    mixin field!(size_t, "worker");

    /// entities of space
    mixin array!(EntityMeta, "entities");
}

class EntityMeta : Data {
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin field!(EntityAccess, "access");
    mixin field!(Data, "context");
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

class Event : Data {
    mixin data;

    mixin field!(EventType, "type");
    mixin field!(string, "tick");
}

public class TickMeta : Data {
    mixin data;

    mixin field!(TickInfo, "info");
    mixin field!(Signal, "trigger");
    mixin field!(TickInfo, "previous");
    mixin field!(Data, "data");
}

class TickInfo : IdData {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(string, "type");
    mixin field!(UUID, "group");
}

class Receptor : Data {
    mixin data;

    mixin field!(string, "signal");
    mixin field!(string, "tick");
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