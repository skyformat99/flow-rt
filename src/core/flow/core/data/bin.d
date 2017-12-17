module flow.core.data.bin;

private import flow.core.data.engine;
private import flow.core.util;
private import std.range;
private import std.traits;
private import std.variant;

private void _bin(Variant val, PropertyInfo pi, ref Appender!(ubyte[]) a, ref string[][string] t) {
    import flow.core.data.engine : Data, TypeDesc;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.uuid : UUID;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            val.get!(bool[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            val.get!(byte[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            val.get!(ubyte[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            val.get!(short[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            val.get!(ushort[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            val.get!(int[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            val.get!(uint[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            val.get!(long[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            val.get!(ulong[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            val.get!(float[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            val.get!(double[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            val.get!(char[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            val.get!(wchar[])._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            val.get!(dchar[])._bin(a, t);
        else if(pi.desc == TypeDesc.UUID)
            val.get!(UUID[])._bin(a, t);
        else if(pi.desc == TypeDesc.SysTime)
            val.get!(SysTime[])._bin(a, t);
        else if(pi.desc == TypeDesc.DateTime)
            val.get!(DateTime[])._bin(a, t);
        else if(pi.desc == TypeDesc.Date)
            val.get!(Date[])._bin(a, t);
        else if(pi.desc == TypeDesc.Duration)
            val.get!(Duration[])._bin(a, t);
        else if(pi.desc == TypeDesc.String)
            val.get!(string[])._bin(a, t);
        else if(pi.desc == TypeDesc.Data)
            val.get!(Data[])._bin(a, t);
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            val.get!(bool)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            val.get!(byte)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            val.get!(ubyte)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            val.get!(short)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            val.get!(ushort)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            val.get!(int)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            val.get!(uint)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            val.get!(long)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            val.get!(ulong)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            val.get!(float)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            val.get!(double)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            val.get!(char)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            val.get!(wchar)._bin(a, t);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            val.get!(dchar)._bin(a, t);
        else if(pi.desc == TypeDesc.UUID)
            val.get!(UUID)._bin(a, t);
        else if(pi.desc == TypeDesc.SysTime)
            val.get!(SysTime)._bin(a, t);
        else if(pi.desc == TypeDesc.DateTime)
            val.get!(DateTime)._bin(a, t);
        else if(pi.desc == TypeDesc.Date)
            val.get!(Date)._bin(a, t);
        else if(pi.desc == TypeDesc.Duration)
            val.get!(Duration)._bin(a, t);
        else if(pi.desc == TypeDesc.String)
            val.get!(string)._bin(a, t);
        else if(pi.desc == TypeDesc.Data)
            val.get!(Data)._bin(a, t);
        else assert(false, "this is an impossible situation");
    }
}

private void _bin(T)(T arr, ref Appender!(ubyte[]) a, ref string[][string] t)
if(
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(T == string)
) {
    arr.length._bin(a, t);
    static if(ElementType!T.sizeof==1) {
        a.put(arr.as!(ubyte[]));
    } else {
        foreach(e; arr) e._bin(a, t);
    }
}

private void _bin(T)(T val, ref Appender!(ubyte[]) a, ref string[][string] t)
if(canHandle!T) {
    import flow.core.data.engine : Data, PropertyInfo;
    import flow.core.util.templates : as;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.bitmanip : nativeToBigEndian;
    import std.uuid : UUID;

    static if(is(T : Data)) {
        if(val !is null) {
            a.put(ubyte.max);
            val.dataType._bin(a, t);
            
            auto props = t.add(val);
            foreach(p; props) {
                auto pi = val.properties[p].as!PropertyInfo;
                pi.get(val)._bin(pi, a, t);
            }
        } else
            a.put(ubyte.init);
    } else static if(is(T == string)) {
        auto arr = cast(ubyte[])val;
        arr.length._bin(a, t);
        a.put(arr);
    } else static if(is(T == UUID))
        return a.put(val.data[]);
    else static if(is(T == SysTime))
        val.toUnixTime._bin(a, t);
    else static if(is(T == DateTime) || is(T == Date))
        val.toISOString._bin(a, t);
    else static if(is(T == Duration))
        val.total!"hnsecs"._bin(a, t);
    else
        a.put(val.nativeToBigEndian[]);
}

/// adds a type info to types and returns serialization order
private string[] add(ref string[][string] t, Data d) {
    if(d.dataType !in t)
        foreach(n, p; d.properties)
            t[d.dataType] ~= n;
    
    return t[d.dataType];
}

private ubyte[] binTypes(string[][string] t) {
    ubyte[] tdata;
    foreach(type, props; t) {
        ubyte[] b;
        b ~= type.bin.pack;
        b ~= props.bin;
        tdata ~= b.pack;
    }
    return tdata;
}

private string[][string] unbinTypes(ubyte[] tdata) {
    import std.range : empty;

    string[][string] t;
    while(!tdata.empty) {
        auto b = tdata.unpack;
        auto dt = b.unpack.unbin!string;
        auto props = b.unbin!(string[]);
        t[dt] = props;
    }
    return t;
}

/// serializes data to binary
ubyte[] bin(T)(T data)
if(
    (canHandle!T && !is(T:Data)) || (
        isArray!T &&
        canHandle!(ElementType!T) && !is(ElementType!T:Data)
    )
) {
    import std.range : appender;
    
    string[][string] t;
    auto a = appender!(ubyte[]);
    data._bin(a, t);
    return a.data;
}

/// serializes data to binary
ubyte[] bin(T)(T data)
if(
    (is(T:Data)) || (
        isArray!T &&
        is(ElementType!T:Data)
    )
) {
    import std.range : appender;
    
    string[][string] t;
    auto a = appender!(ubyte[]);
    data._bin(a, t);
    auto tdata = t.binTypes; // TODO
    return tdata.pack~a.data;
}

/// exception thrwon when binary data is invalid
class InvalidBinException : Exception {
    /// ctor
    this(string msg){super(msg);}
}

/// deserializes binary data
T unbin(T)(ubyte[] arr)
if(
    (canHandle!T && !is(T:Data)) ||
    (isArray!T && canHandle!(ElementType!T) && !is(ElementType!T:Data))
) {
    string[][string] t;
    return arr._unbin!T(t);
}

/// deserializes binary data
T unbin(T)(ubyte[] arr)
if(
    (is(T:Data)) ||
    (isArray!T && is(ElementType!T:Data))
) {
    string[][string] t = arr.unpack.unbinTypes;
    return arr._unbin!T(t);
}

/// deserializes binary data to a given suppoerted array type
private T _unbin(T)(ref ubyte[] arr, string[][string] t)
if(
    isArray!T &&
    canHandle!(ElementType!T) &&
    !is(T == string)
) {
    import std.range : ElementType, popFrontN;

    T uArr;
    auto length = arr._unbin!size_t(t);
    static if(ElementType!T.sizeof==1) {
        uArr ~= arr[0..length].as!T;
        arr.popFrontN(length);
    }
    else
        for(size_t i; i < length; i++)
            uArr ~= arr._unbin!(ElementType!T)(t);
    

    return uArr;
}

/// deserializes binary data to a given supported type
private T _unbin(T)(ref ubyte[] arr, string[][string] t)
if(canHandle!T || is(T:Data)) {
    import flow.core.data.engine : Data, createData, PropertyInfo;
    import flow.core.util.templates : as;
    import std.bitmanip : bigEndianToNative;
    import std.datetime : SysTime, DateTime, Duration, Date, dur;
    import std.range : front, popFront, popFrontN;
    import std.uuid : UUID;

    static if(is(T == string)) {
        auto length = arr._unbin!size_t(t);
        auto val = cast(string)arr[0..length];
        arr.popFrontN(length);
        return val;
    } else static if(is(T == UUID)) {
        auto val = arr[0..16].UUID;
        arr.popFrontN(16);
        return val;
    } else static if(is(T == SysTime)) {
        auto ut = arr._unbin!long(t);
        return SysTime.fromUnixTime(ut);
    }
    else static if(is(T == DateTime) || is(T == Date)) {
        auto str = arr._unbin!string(t);
        return T.fromISOString(str);
    }
    else static if(is(T == Duration)) {
        auto hns = arr._unbin!long(t);
        return dur!"hnsecs"(hns);
    }
    else static if(is(T : Data)) {
        auto isNull = arr.front == ubyte.init;
        arr.popFront;

        if(!isNull) {
            auto dataType = arr._unbin!string(t);
            auto val = createData(dataType);

            if(val !is null) {
                foreach(p; t[dataType])
                    arr._unbin(val, val.properties[p].as!PropertyInfo, t);
                
                return val.as!T;
            } else throw new InvalidBinException("unsupported data type \""~dataType~"\"");
        } else return null;
    }
    else {
        auto val = arr[0..T.sizeof].bigEndianToNative!T;
        arr.popFrontN(T.sizeof);
        return val;
    }
}

private void _unbin(ref ubyte[] arr, Data d, PropertyInfo pi, string[][string] t) {
    import flow.core.data.engine : Data, TypeDesc;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.uuid : UUID;
    import std.variant : Variant;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            pi.set(d, Variant(arr._unbin!(bool[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            pi.set(d, Variant(arr._unbin!(byte[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            pi.set(d, Variant(arr._unbin!(ubyte[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            pi.set(d, Variant(arr._unbin!(short[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            pi.set(d, Variant(arr._unbin!(ushort[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            pi.set(d, Variant(arr._unbin!(int[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            pi.set(d, Variant(arr._unbin!(uint[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            pi.set(d, Variant(arr._unbin!(long[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            pi.set(d, Variant(arr._unbin!(ulong[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            pi.set(d, Variant(arr._unbin!(float[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            pi.set(d, Variant(arr._unbin!(double[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            pi.set(d, Variant(arr._unbin!(char[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            pi.set(d, Variant(arr._unbin!(wchar[])(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            pi.set(d, Variant(arr._unbin!(dchar[])(t)));
        else if(pi.desc == TypeDesc.UUID)
            pi.set(d, Variant(arr._unbin!(UUID[])(t)));
        else if(pi.desc == TypeDesc.SysTime)
            pi.set(d, Variant(arr._unbin!(SysTime[])(t)));
        else if(pi.desc == TypeDesc.DateTime)
            pi.set(d, Variant(arr._unbin!(DateTime[])(t)));
        else if(pi.desc == TypeDesc.Date)
            pi.set(d, Variant(arr._unbin!(Date[])(t)));
        else if(pi.desc == TypeDesc.Duration)
            pi.set(d, Variant(arr._unbin!(Duration[])(t)));
        else if(pi.desc == TypeDesc.String)
            pi.set(d, Variant(arr._unbin!(string[])(t)));
        else if(pi.desc == TypeDesc.Data)
            pi.set(d, Variant(arr._unbin!(Data[])(t)));
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            pi.set(d, Variant(arr._unbin!(bool)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            pi.set(d, Variant(arr._unbin!(byte)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            pi.set(d, Variant(arr._unbin!(ubyte)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            pi.set(d, Variant(arr._unbin!(short)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            pi.set(d, Variant(arr._unbin!(ushort)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            pi.set(d, Variant(arr._unbin!(int)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            pi.set(d, Variant(arr._unbin!(uint)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            pi.set(d, Variant(arr._unbin!(long)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            pi.set(d, Variant(arr._unbin!(ulong)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            pi.set(d, Variant(arr._unbin!(float)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            pi.set(d, Variant(arr._unbin!(double)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            pi.set(d, Variant(arr._unbin!(char)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            pi.set(d, Variant(arr._unbin!(wchar)(t)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            pi.set(d, Variant(arr._unbin!(dchar)(t)));
        else if(pi.desc == TypeDesc.UUID)
            pi.set(d, Variant(arr._unbin!(UUID)(t)));
        else if(pi.desc == TypeDesc.SysTime)
            pi.set(d, Variant(arr._unbin!(SysTime)(t)));
        else if(pi.desc == TypeDesc.DateTime)
            pi.set(d, Variant(arr._unbin!(DateTime)(t)));
        else if(pi.desc == TypeDesc.Date)
            pi.set(d, Variant(arr._unbin!(Date)(t)));
        else if(pi.desc == TypeDesc.Duration)
            pi.set(d, Variant(arr._unbin!(Duration)(t)));
        else if(pi.desc == TypeDesc.String)
            pi.set(d, Variant(arr._unbin!(string)(t)));
        else if(pi.desc == TypeDesc.Data)
            pi.set(d, Variant(arr._unbin!(Data)(t)));
        else assert(false, "this is an impossible situation");
    }
}

unittest { test.header("TEST engine.data.bin: binary serialization of data and member");
    import flow.core.data.engine : TestData, InheritedTestData, TestEnum;
    import std.uuid : parseUUID;

    auto d = new InheritedTestData;
    d.boolean = true;
    d.uinteger = 5;
    d.text = "foo";
    d.uuid = "1bf8eac7-64ee-4cde-aa9e-8877ac2d511d".parseUUID;
    d.inner = new TestData;
    d.inner.integer = 3;
    d.enumeration = TestEnum.Bar;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.enumerationA = [TestEnum.Bar, TestEnum.Foo];
    d.additional = "ble";
    d.ubyteA = [1, 2, 4, 8, 16, 32, 64, 128];

    auto arr = d.bin;
    //ubyte[] cArr = [255, 0, 0, 0, 0, 0, 0, 0, 27, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 73, 110, 104, 101, 114, 105, 116, 101, 100, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, 2, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 18, 102, 108, 111, 119, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 0, 0, 0, 0, 0, 0, 0, 3, 98, 97, 114, 0, 0, 0, 0, 0, 0, 0, 8, 1, 2, 4, 8, 16, 32, 64, 128, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 98, 108, 101, 0, 0, 0, 0, 0, 0, 0, 0, 27, 248, 234, 199, 100, 238, 76, 222, 170, 158, 136, 119, 172, 45, 81, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    //debug(data) writeln(cArr);
    //debug(data) writeln(arr);
    //assert(arr == cArr, "could not serialize data to bin");
    
    auto d2 = arr.unbin!InheritedTestData;
    assert(d2 !is null, "could not deserialize data");
    assert(d2.boolean, "could not deserialize basic scalar value");
    assert(d2.uinteger == 5, "could not deserialize basic scalar value");
    assert(d2.text == "foo", "could not deserialize basic string value");   
    assert(d2.uuid == "1bf8eac7-64ee-4cde-aa9e-8877ac2d511d".parseUUID, "could not deserialize basic uuid value");
    assert(d2.inner !is null && d2.inner !is d.inner, "could not deserialize basic data value");
    assert(d2.enumeration == TestEnum.Bar, "could not deserialize basic enum value");
    assert(d2.inner.integer == 3, "could not deserialize property of basic data value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not deserialize array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not deserialize array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");
    assert(d2.enumerationA.length == 2 && d2.enumerationA[0] == TestEnum.Bar && d2.enumerationA[1] == TestEnum.Foo, "could not deserialize array enum value");

    assert(d2.additional == "ble", "could not deserialize basic scalar value");
test.footer(); }

/// packs ubyte[] so you can add it to a package
ubyte[] pack(ubyte[] data) {
    import std.range : empty;
    
    return data !is null && !data.empty ? [ubyte.max]~data.bin : [ubyte.min];
}

/// removes a packet from package and returns it
ubyte[] unpack(ref ubyte[] data) {
    import std.range : front, popFront, popFrontN;

    string[][string] t;
    auto hasByte = data._unbin!ubyte(t);
    return hasByte ? data._unbin!(ubyte[])(t) : null;
}

unittest { test.header("TEST engine.data.bin: packing/unpacking");
    import std.conv : to;

    ubyte[] a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    ubyte[] b = [10, 9, 8, 7, 6];
    ubyte[] c = null;

    auto pkg = a.pack~b;

    assert(pkg.length == 1+size_t.sizeof+a.length + b.length, "package expected to has a length of "~(1+size_t.sizeof+a.length + b.length).to!string);

    auto na = pkg.unpack;

    assert(na.length == a.length, "unpacked array expected to has a length of "~a.length.to!string~" but truly is "~na.length.to!string~" bytes long");
    assert(pkg.length == b.length, "leftover array expected to has a length of "~a.length.to!string~" but truly is "~pkg.length.to!string~" bytes long");
test.footer(); }