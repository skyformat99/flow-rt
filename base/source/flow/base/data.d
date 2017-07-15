module flow.base.data;

import std.uuid, std.datetime;

import __flow.data, __flow.type, __flow.signal;
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
    
    mixin TField!(FlowPtr, "ptr");
    mixin TField!(uint, "workers");
    mixin TField!(bool, "tracing");
    mixin TField!(bool, "isolateMem");
    mixin TField!(bool, "preventIdTheft");
}

/// referencing a specific process having an unique ptress like udp://hostname:port
class FlowPtr : Data
{
    mixin TData;

    mixin TField!(string, "address");
}

/// scopes an entity can have
enum EntityScope
{
    Local,
    Global
}

class ListeningMeta : Data {
    mixin TData;

    mixin TField!(string, "signal");
    mixin TField!(string, "tick");
}

/// referencing a specific entity 
class EntityPtr : Data {
    mixin TData;

    mixin TField!(string, "id");
    mixin TField!(string, "type");
    mixin TField!(string, "domain");
    mixin TField!(FlowPtr, "flowptr");
}

class EntityConfig : Data {
    mixin TData;

    mixin TField!(bool, "quiet");
}

/// referencing a specific entity 
class EntityInfo : Data {
    mixin TData;

    mixin TField!(EntityPtr, "ptr");
    mixin TField!(EntityScope, "availability");
    mixin TField!(EntityConfig, "config");

    mixin TList!(string, "signals");
}

class EntityMetaDamage : Data {
    mixin TData;

    mixin TField!(string, "msg");
    mixin TField!(Data, "recovery");
}

class EntityMeta : Data {
    mixin TData;

    mixin TList!(EntityMetaDamage, "damages");

    mixin TField!(EntityInfo, "info");
    mixin TList!(EntityMeta, "children");
    mixin TField!(Data, "context");
    mixin TList!(ListeningMeta, "listenings");
    mixin TList!(Signal, "inbound");
    mixin TList!(TickMeta, "ticks");
}

class TickInfo : IdData, IGrouped {
    mixin TData;

    mixin TField!(EntityPtr, "entity");
    mixin TField!(string, "type");
    mixin TField!(UUID, "group");
}

class TickMeta : Data
{
    mixin TData;

    mixin TField!(TickInfo, "info");
    mixin TField!(UUID, "trigger");
    mixin TField!(Signal, "signal");
    mixin TField!(TickMeta, "previous");
    mixin TField!(Data, "data");
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
    mixin TField!(EntityPtr, "entity");
    mixin TField!(string, "tick");
    mixin TField!(string, "nature");
}

class Signal : IdData, IGrouped
{
    mixin TSignal;

    mixin TField!(UUID, "group");
    mixin TField!(bool, "traceable");
    mixin TField!(string, "type");
    mixin TField!(EntityPtr, "source");
}