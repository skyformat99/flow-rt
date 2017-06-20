module __flow.signal;

import core.sync.mutex;
import std.traits, std.uuid, std.datetime, std.range.primitives;

import __flow.data;
import flow.base.dev, flow.base.interfaces, flow.base.data;

mixin template TSignal(T = void)
    if ((is(T == void) || is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{   
    import __flow.data;
    mixin TData;

    static if(!is(T == void))
    {
        mixin TField!(ulong, "seq");
        mixin TField!(T, "data");
    }
}

class Signal : IdData, IGrouped
{
    mixin TSignal;

    mixin TField!(string, "group");
    mixin TField!(bool, "traceable");
    mixin TField!(string, "type");
}

class Unicast : Signal
{
    mixin TSignal;

    mixin TField!(EntityPtr, "source");
    mixin TField!(EntityPtr, "destination");
}

class Multicast : Signal
{
    mixin TSignal;

    mixin TField!(EntityPtr, "source");
    mixin TField!(string, "domain");
}

class Anycast : Signal
{    
    mixin TSignal;

    mixin TField!(EntityPtr, "source");
    mixin TField!(string, "domain");
}