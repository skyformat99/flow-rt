module __flow.signal;

import __flow.data;
import flow.base.data;

import std.uuid, std.datetime;

mixin template signal(T = void)
    if ((is(T == void) || is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))) {   
    static import __flow.data;
    mixin __flow.data.data;

    static if(!is(T == void)) {
        mixin __flow.data.field!(ulong, "seq");
        mixin __flow.data.field!(T, "data");
    }
}