module flow.data.data;

private static import flow.data.engine;

/// identifyable data
class IdData : flow.data.engine.Data {
    private import std.uuid : UUID;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(UUID, "id");
}