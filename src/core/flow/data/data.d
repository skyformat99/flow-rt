module flow.data.data;

private import flow.data.engine;

/// identifyable data
class IdData : Data {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "id");
}