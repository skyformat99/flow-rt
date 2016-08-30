module flow.base.signal;

import core.sync.mutex;
import std.traits, std.uuid, std.datetime, std.range.primitives;

import flow.base.data;
import flow.dev, flow.interfaces, flow.data;

enum CasterState
{
    Pending,
    NoListenerFound,
    NoListenerAcceptable,
    NotSupported,
    Success
}

/// listener is registering and handling signals and if they are anycast also managing their handshake
class Unicast : Data, IUnicast
{
    mixin TData;

    mixin TField!(UUID, "id");
    mixin TField!(UUID, "group");
    mixin TField!(bool, "traceable");
    mixin TField!(string, "type");
    mixin TField!(EntityRef, "source");
    mixin TField!(EntityRef, "destination");
}

class Multicast : Data, IMulticast
{
    mixin TData;

    mixin TField!(UUID, "id");
    mixin TField!(UUID, "group");
    mixin TField!(bool, "traceable");
    mixin TField!(string, "type");
    mixin TField!(EntityRef, "source");
    mixin TField!(string, "domain");
}

class Anycast : Data, IAnycast
{    
    mixin TData;

    mixin TField!(UUID, "id");
    mixin TField!(UUID, "group");
    mixin TField!(bool, "traceable");
    mixin TField!(string, "type");
    mixin TField!(EntityRef, "source");
    mixin TField!(string, "domain");
}

mixin template TSignal(T=void)
    if ((is(T == void) || is(T : IData) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{   
    import flow.base.data;
    mixin TData;

    static if(!is(T == void))
    {
        mixin TField!(ulong, "seq");
        mixin TField!(T, "data");
    }
}