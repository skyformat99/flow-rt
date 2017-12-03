module flow.ipc.make;

private import flow.core;
private import std.uuid;

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0
) {
    return sm.addInProcJunction(id, level, true, true, true);
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level,
    bool isConfirming,
    bool acceptsAnycast,
    bool acceptsMulticast
) {
    import flow.ipc.inproc : InProcessJunctionMeta;
    import flow.util : as;
    
    auto jm = sm.addJunction(
        "flow.ipc.inproc.InProcessJunctionMeta",
        "flow.ipc.inproc.InProcessJunction",
        level,
        isConfirming,
        acceptsAnycast,
        acceptsMulticast
    ).as!InProcessJunctionMeta;
    jm.id = id;

    return jm;
}