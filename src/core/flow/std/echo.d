module flow.std.echo;

private static import flow.data.engine;
private static import flow.data.data;
private static import flow.core.data;

class Ping : flow.core.data.Multicast {
    mixin flow.data.engine.data;
}

class UPing : flow.core.data.Unicast {
    mixin flow.data.engine.data;
}

class Pong : flow.core.data.Unicast {
    private import flow.core.data : EntityPtr;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(EntityPtr, "ptr");
    mixin flow.data.engine.array!(string, "signals");
}