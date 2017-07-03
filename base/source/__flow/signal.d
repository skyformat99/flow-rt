module __flow.signal;

import std.traits, std.uuid, std.datetime, std.range.primitives;

import __flow.data;

mixin template TSignal(T = void)
    if ((is(T == void) || is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{   
    static import __flow.data;
    mixin __flow.data.TData;

    static if(!is(T == void)) {
        mixin __flow.data.TField!(ulong, "seq");
        mixin __flow.data.TField!(T, "data");
    }
}