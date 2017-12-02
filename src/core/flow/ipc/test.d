module flow.ipc.test;

/// imports for tests
version(unittest) {
    import flow.core;
    import flow.data;
    import flow.util;

    import std.uuid;
}

version(unittest) {
    JunctionMeta addInProcJunction(
        SpaceMeta sm,
        UUID id,
        ushort level = 0
    ) {
        return sm.addInProcJunction(id, 0, true, true);
    }

    JunctionMeta addInProcJunction(
        SpaceMeta sm,
        UUID id,
        ushort level,
        bool acceptsAnycast,
        bool acceptsMulticast
    ) {
        import flow.ipc;
        auto jm = createData("flow.core.data.InProcessJunctionMeta").as!InProcessJunctionMeta;
        jm.info = createData("flow.core.data.JunctionInfo").as!JunctionInfo;
        
        jm.id = id;
        jm.level = level;
        jm.info.acceptsAnycast = acceptsAnycast;
        jm.info.acceptsMulticast = acceptsMulticast;

        sm.junctions ~= jm;
        return jm;
    }
}