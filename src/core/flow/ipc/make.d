module flow.ipc.make;

private import flow.core;
private import std.uuid;

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level = 0
) {
    return sm.addInProcJunction(id, level, true, true);
}

/// creates metadata for an in process junction and appeds it to a spaces metadata 
JunctionMeta addInProcJunction(
    SpaceMeta sm,
    UUID id,
    ushort level,
    bool acceptsAnycast,
    bool acceptsMulticast
) {
    import flow.ipc.inproc : InProcessJunctionMeta;
    
    auto jm = new InProcessJunctionMeta;
    jm.info = new JunctionInfo;
    jm.type = "flow.ipc.inproc.InProcessJunction";
    
    jm.id = id;
    jm.level = level;
    jm.info.acceptsAnycast = acceptsAnycast;
    jm.info.acceptsMulticast = acceptsMulticast;

    sm.junctions ~= jm;
    return jm;
}