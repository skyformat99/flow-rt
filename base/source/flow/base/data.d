module flow.base.data;

import std.uuid, std.datetime;

import flow.flow.data, flow.flow.type;
import flow.base.interfaces, flow.base.data;

/// identifyable data
class IdData : Data, IIdentified
{
    mixin TData;

    mixin TField!(UUID, "id");
}

/// configuration object of flow process
class FlowConfig : Data
{
    mixin TData;
    
    mixin TField!(bool, "tracing");
    mixin TField!(bool, "preventIdTheft");
}

/// referencing a specific process having an unique ptress like udp://hostname:port
class FlowPtr : Data
{
    mixin TData;

    mixin TField!(string, "ptress");
}

/// scopes an entity can have
enum EntityScope
{
    Local,
    Global
}

// states an entity can have
enum EntityState
{
    Halted,
    Running,
    Sleeping
}

/// referencing a specific entity 
class EntityPtr : IdData
{
    mixin TData;

    mixin TField!(string, "type");
    mixin TField!(string, "domain");
    mixin TField!(FlowPtr, "process");
}

/// referencing a specific entity 
class EntityInfo : Data
{
    mixin TData;

    mixin TField!(EntityPtr, "ptr");
    mixin TField!(EntityScope, "availability");

    mixin TList!(string, "signals");
}

class ListeningInfo {
    mixin TData;

    mixin TField!(string, "signal");
    mixin TField!(TickMeta, "tick");
}

class EntityMeta : Data
{
    mixin TData;

    mixin TField!(EntityInfo, "info");
    mixin TField!(Data, "context");
    mixin TList!(ListeningInfo, "listenings");
    mixin TList!(Data, "inbound");
    mixin TList!(Data, "outbound");
    mixin TList!(Data, "ticks");
}

class TickInfo : Data, IGrouped {
    mixin TField!(string, "type");
    mixin TField!(string, "group");
}

class TickMeta : Data
{
    mixin TData;

    mixin TField!(TickInfo, "info");
    mixin TField!(Signal, "trigger");
    mixin TField!(TickMeta, "previous");
    mixin TField!(Data, "context");
}


class TraceSignalData : IdData
{
    mixin TData;

    mixin TField!(UUID, "group");
    mixin TField!(SysTime, "time");
    mixin TField!(UUID, "trigger");
    mixin TField!(EntityPtr, "destination");
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

class WrappedSignalData : Data
{
	mixin TData;

    mixin TField!(Data, "signal");
}