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

// states an entity can have
enum EntityState
{
    Halted,
    Running,
    Sleeping
}

/// referencing a specific entity 
class EntityPtr : Data
{
    mixin TData;

    mixin TField!(string, "id");
    mixin TField!(string, "type");
    mixin TField!(string, "domain");
    mixin TField!(FlowPtr, "flowptr");
}

/// referencing a specific entity 
class EntityInfo : Data
{
    mixin TData;

    mixin TField!(EntityPtr, "ptr");
    mixin TField!(EntityScope, "availability");

    mixin TList!(string, "signals");
}

class ListeningMeta : Data {
    mixin TData;

    mixin TField!(string, "signal");
    mixin TField!(string, "tick");
}

class EntityMeta : Data
{
    mixin TData;

    mixin TField!(EntityInfo, "info");
    mixin TField!(Data, "context");
    mixin TList!(EntityMeta, "children");
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

class Unicast : Signal
{
    mixin TSignal;

    mixin TField!(EntityPtr, "destination");
}

class Multicast : Signal
{
    mixin TSignal;

    mixin TField!(string, "domain");
}

class Anycast : Signal
{    
    mixin TSignal;

    mixin TField!(string, "domain");
}

class WrappedSignalData : Data
{
	mixin TData;

    mixin TField!(Signal, "signal");
}