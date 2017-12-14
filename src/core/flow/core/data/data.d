module flow.core.data.data;

private import flow.core.data.engine;

/// identifyable data
class IdData : Data {
    private import std.uuid : UUID;

    mixin data;

    mixin field!(UUID, "id");
}