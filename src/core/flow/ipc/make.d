module flow.ipc.make;

private import flow.core;
private import std.uuid;

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0
) {
    return sm.addInProcJunction(id, level, false, false, false);
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level,
    bool anonymous,
    bool indifferent,
    bool introvert
) {
    import flow.ipc.inproc : InProcessJunctionMeta;
    import flow.util : as;
    
    auto jm = sm.addJunction(
        "flow.ipc.inproc.InProcessJunctionMeta",
        "flow.ipc.inproc.InProcessJunction",
        level,
        anonymous,
        indifferent,
        introvert
    ).as!InProcessJunctionMeta;
    jm.id = id;

    return jm;
}