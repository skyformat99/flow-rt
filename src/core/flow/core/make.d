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

/// creates entity metadata
EntityMeta createEntity(string id, string contextType, ushort level = 0) {
    import flow.data : createData;

    auto em = new EntityMeta;
    em.ptr = new EntityPtr;
    em.ptr.id = id;
    em.context = createData(contextType);
    em.level = level;

    return em;
}

/// creates entity metadata and appends it to a spaces metadata
EntityMeta addEntity(SpaceMeta sm, string id, string contextType, ushort level = 0) {
    auto em = id.createEntity(contextType, level);
    sm.entities ~= em;

    return em;
}

/// adds an event mapping
void addEvent(EntityMeta em, EventType type, string tickType) {
    auto e = new Event;
    e.type = type;
    e.tick = tickType;
    em.events ~= e;
}

/// adds an receptor mapping
void addReceptor(EntityMeta em, string signalType, string tickType) {
    auto r = new Receptor;
    r.signal = signalType;
    r.tick = tickType;
    em.receptors ~= r;
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

/// creates metadata for an junction and appends it to a space
JunctionMeta addJunction(
    SpaceMeta sm,
    string type,
    string junctionType,
    ushort level = 0
) {
    return sm.addJunction(type, junctionType, level, false, false, false);
}

/// creates metadata for an junction and appends it to a space
JunctionMeta addJunction(
    SpaceMeta sm,
    string type,
    string junctionType,
    ushort level,
    bool anonymous,
    bool indifferent,
    bool introvert
) {
    import flow.data : createData;
    import flow.util : as;
    
    auto jm = createData(type).as!JunctionMeta;
    jm.info = new JunctionInfo;
    jm.type = junctionType;
    
    jm.level = level;
    jm.info.anonymous = anonymous;
    jm.info.indifferent = indifferent;
    jm.info.introvert = introvert;

    sm.junctions ~= jm;
    return jm;
}