module flow.core.make;

private import flow.core.data;
private import std.uuid;

/// creates space metadata
SpaceMeta createSpace(string id, size_t worker = 1) {
    auto sm = new SpaceMeta;
    sm.id = id;
    sm.worker = worker;

    return sm;
}

/// creates entity metadata and appends it to a spaces metadata
EntityMeta addEntity(SpaceMeta sm) {
    auto em = new EntityMeta;
    em.ptr = new EntityPtr;

    sm.entities ~= em;

    return em;
}

/// creates tick metadata and appends it to an entities metadata
TickMeta addTick(EntityMeta em, string type, UUID group = randomUUID) {
    auto tm = new TickMeta;
    tm.info = new TickInfo;
    tm.info.id = randomUUID;
    tm.info.type = type;
    tm.info.entity = em.ptr.clone;
    tm.info.group = group;

    em.ticks ~= tm;

    return tm;
}