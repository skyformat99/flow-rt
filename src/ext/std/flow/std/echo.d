module flow.std.echo;

private import flow.core;

/// echo request to n entities
class Ping : Multicast {
    private import flow.data : data;

    mixin data;
}

/// echo request to 1 entity
class UPing : Unicast {
    private import flow.data : data;
    
    mixin data;
}

/// echo response
class Pong : Unicast {
    private import flow.data : data, field, array;
    
    mixin data;

    mixin field!(EntityPtr, "ptr");
    mixin array!(string, "signals");
}