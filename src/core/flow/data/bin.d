module flow.data.bin;

private static import flow.data.engine;
private static import std.range;
private static import std.variant;

private void bin(std.variant.Variant t, flow.data.engine.PropertyInfo pi, ref std.range.Appender!(ubyte[]) a) {
    import flow.data.engine : Data, TypeDesc;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.uuid : UUID;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            t.get!(bool[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            t.get!(byte[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            t.get!(ubyte[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            t.get!(short[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            t.get!(ushort[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            t.get!(int[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            t.get!(uint[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            t.get!(long[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            t.get!(ulong[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            t.get!(float[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            t.get!(double[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            t.get!(char[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            t.get!(wchar[]).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            t.get!(dchar[]).bin(a);
        else if(pi.desc == TypeDesc.UUID)
            t.get!(UUID[]).bin(a);
        else if(pi.desc == TypeDesc.SysTime)
            t.get!(SysTime[]).bin(a);
        else if(pi.desc == TypeDesc.DateTime)
            t.get!(DateTime[]).bin(a);
        else if(pi.desc == TypeDesc.Date)
            t.get!(Date[]).bin(a);
        else if(pi.desc == TypeDesc.Duration)
            t.get!(Duration[]).bin(a);
        else if(pi.desc == TypeDesc.String)
            t.get!(string[]).bin(a);
        else if(pi.desc == TypeDesc.Data)
            t.get!(Data[]).bin(a);
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            t.get!(bool).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            t.get!(byte).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            t.get!(ubyte).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            t.get!(short).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            t.get!(ushort).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            t.get!(int).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            t.get!(uint).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            t.get!(long).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            t.get!(ulong).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            t.get!(float).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            t.get!(double).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            t.get!(char).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            t.get!(wchar).bin(a);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            t.get!(dchar).bin(a);
        else if(pi.desc == TypeDesc.UUID)
            t.get!(UUID).bin(a);
        else if(pi.desc == TypeDesc.SysTime)
            t.get!(SysTime).bin(a);
        else if(pi.desc == TypeDesc.DateTime)
            t.get!(DateTime).bin(a);
        else if(pi.desc == TypeDesc.Date)
            t.get!(Date).bin(a);
        else if(pi.desc == TypeDesc.Duration)
            t.get!(Duration).bin(a);
        else if(pi.desc == TypeDesc.String)
            t.get!(string).bin(a);
        else if(pi.desc == TypeDesc.Data)
            t.get!(Data).bin(a);
        else assert(false, "this is an impossible situation");
    }
}

private void bin(T)(T arr, ref std.range.Appender!(ubyte[]) a)
if(
    std.range.isArray!T &&
    flow.data.engine.canHandle!(std.range.ElementType!T) &&
    !is(T == string)
) {
    arr.length.bin(a);
    foreach(e; arr) e.bin(a);
}

private void bin(T)(T val, ref std.range.Appender!(ubyte[]) a)
if(flow.data.engine.canHandle!T) {
    import flow.data.engine : Data, PropertyInfo;
    import flow.util.templates : as;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.bitmanip : nativeToBigEndian;
    import std.uuid : UUID;

    static if(is(T : Data)) {
        if(val !is null) {
            a.put(ubyte.max);
            val.dataType.bin(a);

            foreach(prop; val.properties) {
                auto pi = prop.as!PropertyInfo;
                pi.get(val).bin(pi, a);
            }
        } else
            a.put(ubyte.init);
    } else static if(is(T == string)) {
        auto arr = cast(ubyte[])val;
        arr.length.bin(a);
        a.put(arr);
    } else static if(is(T == UUID))
        return a.put(val.data[]);
    else static if(is(T == SysTime))
        val.toUnixTime.bin(a);
    else static if(is(T == DateTime) || is(T == Date))
        val.toISOString.bin(a);
    else static if(is(T == Duration))
        val.total!"hnsecs".bin(a);
    else
        a.put(val.nativeToBigEndian[]);
}

/// serializes data to binary
ubyte[] bin(T)(T data)
if(is(T: flow.data.engine.Data)) {
    import std.range : appender;
    auto a = appender!(ubyte[]);
    data.bin(a);
    return a.data;
}

/// exception thrwon when binary data is invalid
class InvalidBinException : Exception {
    /// ctor
    this(string msg){super(msg);}
}

/// deserializes binary data to a given suppoerted array type
T unbin(T)(ref ubyte[] arr)
if(
    std.range.isArray!T &&
    flow.data.engine.canHandle!(std.range.ElementType!T) &&
    !is(T == string)
) {
    import std.range : ElementType;

    T uArr;
    auto length = arr.unbin!size_t;
    for(size_t i; i < length; i++)
        uArr ~= arr.unbin!(ElementType!T);

    return uArr;
}

/// deserializes binary data to a given supported type
T unbin(T)(ref ubyte[] arr)
if(flow.data.engine.canHandle!T) {
    import flow.data.engine : Data, createData, PropertyInfo;
    import flow.util.templates : as;
    import std.bitmanip : bigEndianToNative;
    import std.datetime : SysTime, DateTime, Duration, Date, dur;
    import std.range : front, popFront, popFrontN;
    import std.uuid : UUID;

    static if(is(T == string)) {
        auto length = arr.unbin!size_t;
        auto val = cast(string)arr[0..length];
        arr.popFrontN(length);
        return val;
    } else static if(is(T == UUID)) {
        auto val = arr[0..16].UUID;
        arr.popFrontN(16);
        return val;
    } else static if(is(T == SysTime)) {
        auto ut = arr.unbin!long;
        return SysTime.fromUnixTime(ut);
    }
    else static if(is(T == DateTime) || is(T == Date)) {
        auto str = arr.unbin!string;
        return T.fromISOString(str);
    }
    else static if(is(T == Duration)) {
        auto hns = arr.unbin!long;
        return dur!"hnsecs"(hns);
    }
    else static if(is(T : Data)) {
        auto isNull = arr.front == ubyte.init;
        arr.popFront;

        if(!isNull) {
            auto dataType = arr.unbin!string;
            auto val = createData(dataType);

            if(val !is null) {
                foreach(pi; val.properties) {
                    arr.unbin(val, pi.as!PropertyInfo);
                }
                
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

private void unbin(ref ubyte[] arr, flow.data.engine.Data d, flow.data.engine.PropertyInfo pi) {
    import flow.data.engine : Data, TypeDesc;
    import std.datetime : SysTime, DateTime, Duration, Date;
    import std.uuid : UUID;
    import std.variant : Variant;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            pi.set(d, Variant(arr.unbin!(bool[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            pi.set(d, Variant(arr.unbin!(byte[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            pi.set(d, Variant(arr.unbin!(ubyte[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            pi.set(d, Variant(arr.unbin!(short[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            pi.set(d, Variant(arr.unbin!(ushort[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            pi.set(d, Variant(arr.unbin!(int[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            pi.set(d, Variant(arr.unbin!(uint[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            pi.set(d, Variant(arr.unbin!(long[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            pi.set(d, Variant(arr.unbin!(ulong[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            pi.set(d, Variant(arr.unbin!(float[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            pi.set(d, Variant(arr.unbin!(double[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            pi.set(d, Variant(arr.unbin!(char[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            pi.set(d, Variant(arr.unbin!(wchar[])));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            pi.set(d, Variant(arr.unbin!(dchar[])));
        else if(pi.desc == TypeDesc.UUID)
            pi.set(d, Variant(arr.unbin!(UUID[])));
        else if(pi.desc == TypeDesc.SysTime)
            pi.set(d, Variant(arr.unbin!(SysTime[])));
        else if(pi.desc == TypeDesc.DateTime)
            pi.set(d, Variant(arr.unbin!(DateTime[])));
        else if(pi.desc == TypeDesc.Date)
            pi.set(d, Variant(arr.unbin!(Date[])));
        else if(pi.desc == TypeDesc.Duration)
            pi.set(d, Variant(arr.unbin!(Duration[])));
        else if(pi.desc == TypeDesc.String)
            pi.set(d, Variant(arr.unbin!(string[])));
        else if(pi.desc == TypeDesc.Data)
            pi.set(d, Variant(arr.unbin!(Data[])));
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            pi.set(d, Variant(arr.unbin!(bool)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            pi.set(d, Variant(arr.unbin!(byte)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            pi.set(d, Variant(arr.unbin!(ubyte)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            pi.set(d, Variant(arr.unbin!(short)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            pi.set(d, Variant(arr.unbin!(ushort)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            pi.set(d, Variant(arr.unbin!(int)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            pi.set(d, Variant(arr.unbin!(uint)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            pi.set(d, Variant(arr.unbin!(long)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            pi.set(d, Variant(arr.unbin!(ulong)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            pi.set(d, Variant(arr.unbin!(float)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            pi.set(d, Variant(arr.unbin!(double)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            pi.set(d, Variant(arr.unbin!(char)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            pi.set(d, Variant(arr.unbin!(wchar)));
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            pi.set(d, Variant(arr.unbin!(dchar)));
        else if(pi.desc == TypeDesc.UUID)
            pi.set(d, Variant(arr.unbin!(UUID)));
        else if(pi.desc == TypeDesc.SysTime)
            pi.set(d, Variant(arr.unbin!(SysTime)));
        else if(pi.desc == TypeDesc.DateTime)
            pi.set(d, Variant(arr.unbin!(DateTime)));
        else if(pi.desc == TypeDesc.Date)
            pi.set(d, Variant(arr.unbin!(Date)));
        else if(pi.desc == TypeDesc.Duration)
            pi.set(d, Variant(arr.unbin!(Duration)));
        else if(pi.desc == TypeDesc.String)
            pi.set(d, Variant(arr.unbin!(string)));
        else if(pi.desc == TypeDesc.Data)
            pi.set(d, Variant(arr.unbin!(Data)));
        else assert(false, "this is an impossible situation");
    }
}

unittest {
    import flow.data.engine : TestData, InheritedTestData, TestEnum;
    import std.stdio : writeln;
    import std.uuid : parseUUID;

    writeln("testing binary serialization of data and member");

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
}