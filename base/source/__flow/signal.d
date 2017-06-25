module __flow.signal;

import std.traits, std.uuid, std.datetime, std.range.primitives;

import __flow.data;
import flow.base.dev, flow.base.interfaces;

mixin template TSignal(T = void)
    if ((is(T == void) || is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{   
    import __flow.data;
    mixin TData;

    static if(!is(T == void)) {
        mixin TField!(ulong, "seq");
        mixin TField!(T, "data");
    }
}