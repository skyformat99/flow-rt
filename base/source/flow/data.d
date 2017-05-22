module flow.data;

import std.uuid, std.datetime;

import flow.base.data, flow.base.type;
import flow.interfaces, flow.data;

/// identifyable data
class IdData : Data, IIdentified
{
    mixin TData;

    mixin TField!(UUID, "id");
}

/// referencing a specific process having an unique address like udp://hostname:port
class ProcessRef : Data
{
    mixin TData;

    mixin TField!(string, "address");
}

/// referencing a specific entity 
class EntityRef : IdData
{
    mixin TData;

    mixin TField!(string, "type");
    mixin TField!(ProcessRef, "process");
}

/// referencing a specific entity 
class EntityInfo : Data
{
    mixin TData;

    mixin TField!(EntityRef, "reference");
    mixin TField!(string, "domain");
    mixin TField!(EntityScope, "availability");

    mixin TList!(string, "signals");

    mixin TField!(Data, "settings");
}

class TraceSignalData : IdData
{
    mixin TData;

    mixin TField!(UUID, "group");
    mixin TField!(SysTime, "time");
    mixin TField!(UUID, "trigger");
    mixin TField!(EntityRef, "destination");
    mixin TField!(string, "type");
    mixin TField!(bool, "success");
    mixin TField!(string, "nature");
}

class TraceTickData : IdData
{
    mixin TData;
    
    mixin TField!(UUID, "group");
    mixin TField!(SysTime, "time");
    mixin TField!(UUID, "trigger");
    mixin TField!(string, "entityType");
    mixin TField!(UUID, "entityId");
    mixin TField!(UUID, "ticker");
    mixin TField!(ulong, "seq");
    mixin TField!(string, "tick");
    mixin TField!(string, "nature");
}