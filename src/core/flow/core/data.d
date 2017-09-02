module flow.core.data;

import flow.core.util;

import std.traits;
import std.variant;
import std.range;
import std.uuid;
import std.datetime;
import std.json;

//import msgpack;

template canHandle(T) {
    enum canHandle =
        is(T == bool) ||
        is(T == byte) ||
        is(T == ubyte) ||
        is(T == short) ||
        is(T == ushort) ||
        is(T == int) ||
        is(T == uint) ||
        is(T == long) ||
        is(T == ulong) ||
        is(T == float) ||
        is(T == double) ||
        is(T == char) ||
        is(T == wchar) ||
        is(T == dchar) ||
        (is(T == enum) && is(OriginalType!T == bool)) ||
        (is(T == enum) && is(OriginalType!T == byte)) ||
        (is(T == enum) && is(OriginalType!T == ubyte)) ||
        (is(T == enum) && is(OriginalType!T == short)) ||
        (is(T == enum) && is(OriginalType!T == ushort)) ||
        (is(T == enum) && is(OriginalType!T == int)) ||
        (is(T == enum) && is(OriginalType!T == uint)) ||
        (is(T == enum) && is(OriginalType!T == long)) ||
        (is(T == enum) && is(OriginalType!T == ulong)) ||
        (is(T == enum) && is(OriginalType!T == float)) ||
        (is(T == enum) && is(OriginalType!T == double)) ||
        (is(T == enum) && is(OriginalType!T == char)) ||
        (is(T == enum) && is(OriginalType!T == wchar)) ||
        (is(T == enum) && is(OriginalType!T == dchar)) ||
        is(T == UUID) ||
        is(T == SysTime) ||
        is(T == DateTime) ||
        is(T == Date) ||
        is(T == Duration) ||
        is(T == string) ||        
        is(T : Data);
}

string fqn(Data d) {return d.dataType;}

enum TypeDesc {
    Scalar,
    UUID,
    SysTime,
    DateTime,
    Date,
    Duration,
    String,
    Data
}

class TypeMismatchException : Exception {this(){super(string.init);}}

/// runtime inforamtions of a data property
struct PropertyInfo {
	private TypeInfo _info;
    private string _type;
    private string _name;
    private bool _array;
    private TypeDesc _desc;

    private Variant function(Data) _getter;
	private bool function(Data, Variant) _setter;
	private bool function(Data, Data) _equals;

    @property TypeInfo info() {return this._info;}
    @property string type() {return this._type;}
    @property string name() {return this._name;}
    @property bool array() {return this._array;}
    @property TypeDesc desc() {return this._desc;}

    Variant get(Data d) {
        return _getter(d);
    }

    bool set(Data d, Variant v) {
        return _setter(d, v);
    }

    bool equal(Data a, Data b) {
        return _equals(a, b);
    }
}

abstract class Data {
    @property shared(PropertyInfo[string]) properties(){return null;}

    abstract @property string dataType();

    override bool opEquals(Object o) {
        auto c = o.as!Data;
        if(c !is null && this.dataType == c.dataType) {
            foreach(pi; this.properties)
                if(!pi.as!PropertyInfo.equal(this, c)) {
                    return false;
                }
            
            return true;
        } else return false;
    }

    @property Data clone() {
        import std.stdio;
        Data c = Object.factory(this.dataType).as!Data;

        foreach(prop; this.properties) {
            auto pi = prop.as!PropertyInfo;
            auto val = pi.get(this);
            pi.set(c, val.clone(pi));
        }

        return c;
    }
}

mixin template data() {
    static import __flowutil = flow.core.util, __flowdata = flow.core.data;
    debug(data) pragma(msg, "\tdata "~__flowutil.fqn!(typeof(this)));

    shared static __flowdata.PropertyInfo[string] Properties;
    override @property shared(__flowdata.PropertyInfo[string]) properties() {
        return Properties;
    }

    override @property string dataType() {return __flowutil.fqn!(typeof(this));}
    
    shared static this() {
		static if(__flowutil.fqn!(typeof(super)) != "flow.core.data.Data")
            foreach(n, i; super.Properties)
                Properties[n] = i;
    }

    override @property typeof(this) clone() {
        return cast(typeof(this))super.clone;
    }
}

mixin template field(T, string name) if (canHandle!T) {
    debug(data) pragma(msg, "\t\t"~T.stringof~" "~name);

    shared static this() {
        import flow.core.util, flow.core.data;

        import std.variant, std.traits;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ? "t."~name~".as!Data" : "cast("~OriginalType!(T).stringof~")t."~name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~")) {
                t."~name~" = cast("~T.stringof~")"~(is(T : Data) ? "v.get!Data().as!"~T.stringof : "v.get!("~OriginalType!(T).stringof~")")~";
                return true;
            } else return false;
        };");

        mixin("bool function(Data, Data) equals = (a, b) {
            static if(is(T == float) || is(T == double)) {
                import std.math;
                return a.as!(typeof(this))."~name~".isIdentical(b.as!(typeof(this))."~name~");
            } else
                return a.as!(typeof(this))."~name~" == b.as!(typeof(this))."~name~";
        };");

        Properties[name] = TPropertyHelper!(T, name).getFieldInfo(getter, setter, equals).as!(shared(PropertyInfo));
    }

    // field
    mixin(T.stringof~" "~name~";");
}

mixin template array(T, string name) if (canHandle!T) {
    debug(data) pragma(msg, "\t\t"~T.stringof~"[] "~name);

    shared static this() {
        import flow.core.util, flow.core.data;

        import std.variant, std.traits;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ? "t."~name~".as!(Data[])" : "cast("~OriginalType!(T).stringof~"[])t."~name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : OriginalType!(T).stringof)~"[])) {
                t."~name~" = cast("~T.stringof~"[])"~(is(T : Data) ? "v.get!(Data[])().as!("~T.stringof~"[])" : "v.get!("~OriginalType!(T).stringof~"[])")~";
                return true;
            } else return false;
        };");

        mixin("bool function(Data, Data) equals = (a, b) {            
            import std.algorithm.comparison;
            static if(is(T == float) || is(T == double)) {
                import std.math;
                return a.as!(typeof(this))."~name~".equal!((x, y) => x.isIdentical(y))(b.as!(typeof(this))."~name~");
            } else {
                return a.as!(typeof(this))."~name~".equal(b.as!(typeof(this))."~name~");
            }
        };");

        Properties[name] = TPropertyHelper!(T, name).getArrayInfo(getter, setter, equals).as!(shared(PropertyInfo));
    }
    
    // array
    mixin(T.stringof~"[] "~name~";");
}

template TPropertyHelper(T, string name) {
    PropertyInfo getFieldInfo(Variant function(Data) getter, bool function(Data, Variant) setter, bool function(Data, Data) equals) {
        PropertyInfo pi;

        static if(isScalarType!T) {
            pi._type = OriginalType!(T).stringof;
            pi._info = typeid(OriginalType!T);
        } else {
            pi._type = T.stringof;
            pi._info = typeid(T);
        }

        pi._name = name;
        pi._array = false;
        pi._getter = getter;
        pi._setter = setter;
        pi._equals = equals;

        if(isScalarType!T) pi._desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi._desc = TypeDesc.Data;
        else if(is(T == UUID)) pi._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) pi._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) pi._desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi._desc = TypeDesc.Date;
        else if(is(T == Duration)) pi._desc = TypeDesc.Duration;
        else if(is(T == string)) pi._desc = TypeDesc.String;

        return pi;
    }

    PropertyInfo getArrayInfo(Variant function(Data) getter, bool function(Data, Variant) setter, bool function(Data, Data) equals) {
        PropertyInfo pi;
        
        static if(isScalarType!T) {
            pi._type = OriginalType!(T).stringof;
            pi._info = typeid(OriginalType!T);
        } else {
            pi._type = T.stringof;
            pi._info = typeid(T);
        }
        
        pi._name = name;
        pi._array = true;
        pi._getter = getter;
        pi._setter = setter;
        pi._equals = equals;

        if(isScalarType!T) pi._desc = TypeDesc.Scalar;
        else if(is(T : Data)) pi._desc = TypeDesc.Data;
        else if(is(T == UUID)) pi._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) pi._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) pi._desc = TypeDesc.DateTime;
        else if(is(T == Date)) pi._desc = TypeDesc.Date;
        else if(is(T == Duration)) pi._desc = TypeDesc.Duration;
        else if(is(T == string)) pi._desc = TypeDesc.String;

        return pi;
    }
}

version (unittest) enum TestEnum {
    Foo,
    Bar
}

version (unittest) class TestData : Data {
    mixin data;

    // testing basic fields
    mixin field!(TestData, "inner");
    mixin field!(bool, "boolean");
    mixin field!(long, "integer");
    mixin field!(ulong, "uinteger");
    mixin field!(double, "floating");
    mixin field!(TestEnum, "enumeration");
    mixin field!(UUID, "uuid");
    mixin field!(SysTime, "sysTime");
    mixin field!(DateTime, "dateTime");
    mixin field!(Duration, "duration");
    mixin field!(string, "text");

    // testing array fields
    mixin array!(TestData, "innerA");
    mixin array!(bool, "booleanA");
    mixin array!(long, "integerA");
    mixin array!(ulong, "uintegerA");
    mixin array!(double, "floatingA");
    mixin array!(TestEnum, "enumerationA");
    mixin array!(UUID, "uuidA");
    mixin array!(SysTime, "sysTimeA");
    mixin array!(DateTime, "dateTimeA");
    mixin array!(Duration, "durationA");
    mixin array!(string, "textA");

    // testing for module name conflicts
    mixin field!(string, "flow");

    // nan != nan
    mixin field!(double, "nan");
    mixin array!(double, "nanA");
}

version(unittest) class InheritedTestData : TestData {
    mixin data;

    mixin field!(string, "additional");
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing static data usage");
    
    auto d = new InheritedTestData;
    assert(d !is null, "could not statically create instance of data");
    assert(d.integer is long.init && d.integerA.empty && d.text is string.init && d.inner is null, "data is not initialized correctly at static creation");
    
    d.floating = 0.005; assert(d.floating == 0.005, "could not set basic scalar value");
    d.uinteger = 5; assert(d.uinteger == 5, "could not set basic scalar value");
    d.text = "foo"; assert(d.text == "foo", "could not set basic string value");    
    d.inner = new TestData; assert(d.inner !is null, "could not set basic data value");
    d.inner.integer = 3; assert(d.inner.integer == 3, "could not set property of basic data value");
    d.enumeration = TestEnum.Bar; assert(d.enumeration == TestEnum.Bar, "could not ser property of basic enum value");
    d.uintegerA ~= 3; d.uintegerA ~= 4; assert(d.uintegerA.length == 2 && d.uintegerA[0] == 3 && d.uintegerA[1] == 4, "could not set array scalar value");
    d.uintegerA = [1]; assert(d.uintegerA.length == 1 && d.uintegerA[0] == 1, "could not set array scalar value");
    d.textA ~= "foo"; d.textA ~= "bar"; assert(d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    d.textA = ["bla"]; assert(d.textA.length == 1 && d.textA[0] == "bla", "could not set array string value");
    d.innerA ~= new TestData; d.innerA ~= new TestData; assert(d.innerA.length == 2 && d.innerA[0] !is null && d.innerA[1] !is null && d.innerA[0] !is d.innerA[1], "could not set array data value");
    d.innerA = [new TestData]; assert(d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    d.enumerationA ~= TestEnum.Bar; d.enumerationA ~= TestEnum.Foo; assert(d.enumerationA.length == 2 && d.enumerationA[0] == TestEnum.Bar && d.enumerationA[1] == TestEnum.Foo, "could not set array enum value");
    d.enumerationA = [TestEnum.Bar]; assert(d.enumerationA.length == 1 && d.enumerationA[0] == TestEnum.Bar, "could not set array enum value");
    d.additional = "ble"; assert(d.additional == "ble", "could not set second level basic scalar");
    d.nanA ~= double.nan; assert(d.nanA.length == 1 && d.nanA[0] is double.nan, "could not set second level basic scalar");
}

Data createData(string name) {
    return Object.factory(name).as!Data;
}

class PropertyNotExistingException : Exception {this(){super(string.init);}}

private Variant get(Data d, string name){
    if(name in d.properties)
        return d.properties[name].as!PropertyInfo.get(d);
    else
        throw new PropertyNotExistingException;
}

T get(T)(Data d, string name) if(is(T : Data)) {
    return d.get(name).get!Data().as!T;
}

T get(T)(Data d, string name) if(isArray!T && is(ElementType!T : Data)) {
    return d.get(name).get!(Data[])().as!T;
}

T get(T)(Data d, string name) if(canHandle!T && !is(T : Data)) {
    return cast(T)d.get(name).get!(OriginalType!T)();
}

T get(T)(Data d, string name) if(!is(T == string) && isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data)) {
    return cast(T)d.get(name).get!(OriginalType!(ElementType!T)[])();
}

private bool set(Data d, string name, Variant val) {
    if(name in d.properties)
        return d.properties[name].as!PropertyInfo.set(d, val);
    else
        throw new PropertyNotExistingException;
}

bool set(T)(Data d, string name, T val) if(is(T : Data)) {
    return d.set(name, Variant(val.as!Data));
}

bool set(T)(Data d, string name, T val) if(isArray!T && is(ElementType!T : Data)) {
    return d.set(name, Variant(val.as!(Data[])));
}

bool set(T)(Data d, string name, T val) if(canHandle!T && !is(T : Data)) {
    return d.set(name, Variant(cast(OriginalType!T)val));
}

bool set(T)(Data d, string name, T val) if(!is(T == string) && isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data)) {
    return d.set(name, Variant(cast(OriginalType!(ElementType!T)[])val));
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing dynamic data usage");

    auto d = "flow.core.data.InheritedTestData".createData().as!InheritedTestData;
    assert(d !is null, "could not dynamically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at dynamic creation");

    assert(d.set("floating", 0.005) && d.floating == 0.005, "could not set basic scalar value");
    assert(d.get!double("floating") == 0.005, "could not get basic scalar value");

    assert(d.set("uinteger", 4) && d.uinteger == 4, "could not set basic scalar value");
    assert(d.get!ulong("uinteger") == 4, "could not get basic scalar value");
    
    assert(d.set("text", "foo") && d.text == "foo", "could not set basic string value");
    assert(d.get!string("text") == "foo", "could not get basic string value");
    
    assert(d.set("inner", new TestData) && d.inner !is null, "could not set basic data value");
    assert(d.get!TestData("inner") !is null, "could not get basic data value");
    assert(d.set("inner", null.as!TestData) && d.inner is null, "could not set basic data value");
    assert(d.get!TestData("inner") is null, "could not get basic data value");

    assert(d.set("enumeration", TestEnum.Bar) && d.enumeration == TestEnum.Bar, "could not set basic enum value");
    assert(d.get!TestEnum("enumeration") == TestEnum.Bar, "could not get basic enum value");
    
    assert(d.set("integerA", [2L, 3L, 4L]) && d.integerA.length == 3 && d.integerA[0] == 2 && d.integerA[1] == 3 && d.integerA[2] == 4, "could not set array scalar value");
    assert(d.get!(long[])("integerA")[0] == 2L, "could not get array scalar value");
    
    assert(d.set("textA", ["foo", "bar"]) && d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    assert(d.get!(string[])("textA")[0] == "foo", "could not get array string value");
    
    assert(d.set("innerA", [new TestData]) && d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    assert(d.get!(TestData[])("innerA")[0] !is null, "could not get array data value");
    
    assert(d.set("enumerationA", [TestEnum.Bar, TestEnum.Foo]) && d.enumerationA.length == 2 && d.enumerationA[0] == TestEnum.Bar && d.enumerationA[1] == TestEnum.Foo, "could not set array enum value");
    assert(d.get!(TestEnum[])("enumerationA")[0] == TestEnum.Bar, "could not get array enum value");
    
    assert(d.set("additional", "ble") && d.additional == "ble", "could not set second level basic scalar value");
    assert(d.get!string("additional") == "ble", "could not get second level basic scalar value");
    
    assert(d.set("nanA", [double.nan]) && d.nanA.length == 1 && d.nanA[0] is double.nan, "could not set array data value");
    assert(d.get!(double[])("nanA")[0] is double.nan, "could not get array data value");
}

T clone(T)(T arr) if(isArray!T && is(ElementType!T : Data)) {
    T cArr;
    foreach(e; arr) cArr ~= cast(ElementType!T)e.clone;

    return cArr;
}

T clone(T)(T arr) if(isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data)) {
    T cArr;
    foreach(e; arr) cArr ~= e;

    return cArr;
}

private Variant clone(Variant t, PropertyInfo pi) {
    import std.stdio;

    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return Variant(t.get!(bool[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return Variant(t.get!(byte[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return Variant(t.get!(ubyte[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return Variant(t.get!(short[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return Variant(t.get!(ushort[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return Variant(t.get!(int[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return Variant(t.get!(uint[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return Variant(t.get!(long[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return Variant(t.get!(ulong[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return Variant(t.get!(float[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return Variant(t.get!(double[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return Variant(t.get!(char[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return Variant(t.get!(wchar[]).clone);
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return Variant(t.get!(dchar[]).clone);
        else if(pi.desc == TypeDesc.UUID)
            return Variant(t.get!(UUID[]).clone);
        else if(pi.desc == TypeDesc.SysTime)
            return Variant(t.get!(SysTime[]).clone);
        else if(pi.desc == TypeDesc.DateTime)
            return Variant(t.get!(DateTime[]).clone);
        else if(pi.desc == TypeDesc.Date)
            return Variant(t.get!(Date[]).clone);
        else if(pi.desc == TypeDesc.Duration)
            return Variant(t.get!(Duration[]).clone);
        else if(pi.desc == TypeDesc.String)
            return Variant(t.get!(string[]).clone);
        else if(pi.desc == TypeDesc.Data)
            return Variant(t.get!(Data[]).clone);
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Data) {
            auto d = t.get!(Data);
            return Variant(d !is null ? d.clone : null);
        }
        else return t;
    }
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing clone and == of data and member");

    auto d = new InheritedTestData;
    d.uinteger = 5;
    d.text = "foo";
    d.inner = new TestData;
    d.inner.integer = 3;
    d.enumeration = TestEnum.Bar;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.enumerationA = [TestEnum.Bar, TestEnum.Foo];
    d.additional = "ble";

    auto d2 = d.clone().as!InheritedTestData;
 
    assert(d !is d2, "clones references are matching");
    assert(d2.uinteger == 5, "could not clone basic scalar value");
    assert(d2.text == "foo", "could not clone basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not clone basic data value");
    assert(d2.inner.integer == 3, "could not clone property of basic data value");
    assert(d2.enumeration == TestEnum.Bar, "could not clone basic enum value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not clone array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not clone array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");
    assert(d2.enumerationA.length == 2 && d2.enumerationA[0] == TestEnum.Bar && d2.enumerationA[1] == TestEnum.Foo && d2.enumerationA !is d.enumerationA, "could not clone array enum value");

    assert(d2.additional == "ble", "could not clone basic scalar value");

    assert(d == d2, "clones don't ==");
}

private JSONValue jsonValue(Variant t, PropertyInfo pi) {
    import std.stdio;
    if(pi.array) {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return t.get!(bool[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return t.get!(byte[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return t.get!(ubyte[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return t.get!(short[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return t.get!(ushort[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return t.get!(int[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return t.get!(uint[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return t.get!(long[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return t.get!(ulong[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return t.get!(float[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return t.get!(double[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return t.get!(char[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return t.get!(wchar[]).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return t.get!(dchar[]).jsonValue;
        else if(pi.desc == TypeDesc.UUID)
            return t.get!(UUID[]).jsonValue;
        else if(pi.desc == TypeDesc.SysTime)
            return t.get!(SysTime[]).jsonValue;
        else if(pi.desc == TypeDesc.DateTime)
            return t.get!(DateTime[]).jsonValue;
        else if(pi.desc == TypeDesc.Date)
            return t.get!(Date[]).jsonValue;
        else if(pi.desc == TypeDesc.Duration)
            return t.get!(Duration[]).jsonValue;
        else if(pi.desc == TypeDesc.String)
            return t.get!(string[]).jsonValue;
        else if(pi.desc == TypeDesc.Data)
            return t.get!(Data[]).jsonValue;
        else assert(false, "this is an impossible situation");
    } else {
        if(pi.desc == TypeDesc.Scalar && pi.info == typeid(bool))
            return t.get!(bool).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(byte))
            return t.get!(byte).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ubyte))
            return t.get!(ubyte).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(short))
            return t.get!(short).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ushort))
            return t.get!(ushort).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(int))
            return t.get!(int).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(uint))
            return t.get!(uint).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(long))
            return t.get!(long).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(ulong))
            return t.get!(ulong).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(float))
            return t.get!(float).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(double))
            return t.get!(double).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(char))
            return t.get!(char).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(wchar))
            return t.get!(wchar).jsonValue;
        else if(pi.desc == TypeDesc.Scalar && pi.info == typeid(dchar))
            return t.get!(dchar).jsonValue;
        else if(pi.desc == TypeDesc.UUID)
            return t.get!(UUID).jsonValue;
        else if(pi.desc == TypeDesc.SysTime)
            return t.get!(SysTime).jsonValue;
        else if(pi.desc == TypeDesc.DateTime)
            return t.get!(DateTime).jsonValue;
        else if(pi.desc == TypeDesc.Date)
            return t.get!(Date).jsonValue;
        else if(pi.desc == TypeDesc.Duration)
            return t.get!(Duration).jsonValue;
        else if(pi.desc == TypeDesc.String)
            return t.get!(string).jsonValue;
        else if(pi.desc == TypeDesc.Data)
            return t.get!(Data).jsonValue;
        else assert(false, "this is an impossible situation");
    }
}

private JSONValue jsonValue(T)(T arr) if(isArray!T && (is(ElementType!T : Data) || is(ElementType!T == UUID) || is(ElementType!T == SysTime) || is(ElementType!T == DateTime) || is(ElementType!T == Date) || is(ElementType!T == Duration))) {
    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= e.jsonValue;

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue jsonValue(T)(T arr) if(isArray!T && canHandle!(ElementType!T) && !is(T == string) && !is(ElementType!T : Data) && !is(ElementType!T == UUID) && !is(ElementType!T == SysTime) && !is(ElementType!T == DateTime) && !is(ElementType!T == Date) && !is(ElementType!T == Duration)) {
    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= JSONValue(e);

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue jsonValue(T)(T val) if(canHandle!T && !is(T : Data) && !is(T == float) && !is(T == double) && !is(T == UUID) && !is(T == SysTime) && !is(T == DateTime) && !is(T == Date) && !is(T == Duration)) {
    return val is T.init ? JSONValue(null) : JSONValue(val);
}

private JSONValue jsonValue(T)(T val) if(is(T == float) || is(T == double)) {
    import std.math;
    return val is T.init || isNaN(val) ? JSONValue(null) : JSONValue(val);
}

private JSONValue jsonValue(T)(T val) if(is(T == UUID)) {
    return val is T.init ? JSONValue(null) : JSONValue(val.toString());
}

private JSONValue jsonValue(T)(T val) if(is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
    return val is T.init ? JSONValue(null) : JSONValue(val.toISOExtString());
}

private JSONValue jsonValue(T)(T val) if(is(T == Duration)) {
    return val is T.init ? JSONValue(null) : JSONValue(val.total!"hnsecs");
}

private JSONValue jsonValue(T)(T data) if(is(T : Data)) {
    JSONValue c;
    if(data !is null) {
        c = JSONValue(["dataType" : JSONValue(data.dataType)]);

        foreach(prop; data.properties) {
            auto pi = prop.as!PropertyInfo;
            auto val = pi.get(data);
            auto j = val.jsonValue(pi);
            if(!j.isNull) c.object[pi.name] = j;
        }
    }

    return c;
}

enum JsonSerializer {
    StdJson
}

string json(T)(T data, bool pretty = false, JsonSerializer serializer = JsonSerializer.StdJson) {
    switch(serializer) {
        case JsonSerializer.StdJson:
            return pretty ? data.jsonValue.toPrettyString : data.jsonValue.toString;
        default:
            throw new NotImplementedError;
    }
}

class InvalidJsonException : Exception {this(string msg){super(msg);}}
Data createDataFromJson(string str, JsonSerializer serializer = JsonSerializer.StdJson) {
    switch(serializer) {
        case JsonSerializer.StdJson:
            return str.parseJSON.createData;
        default:
            throw new NotImplementedError;
    }
}

private Data createData(JSONValue j) {
    auto dt = j["dataType"].str;
    if(dt == string.init)
        throw new InvalidJsonException("json object has no dataType");

    auto d = dt.createData();
    foreach(string name, e; j) {
        if(name != "dataType") {
            if(name !in d.properties)
                throw new InvalidJsonException("\""~d.dataType~"\" contains no property named \""~name~"\"");
        
            auto pi = d.properties[name].as!PropertyInfo;
            Variant val;
            if(!val.hasValue) val = e.get!bool(d, pi);
            if(!val.hasValue) val = e.get!byte(d, pi);
            if(!val.hasValue) val = e.get!ubyte(d, pi);
            if(!val.hasValue) val = e.get!short(d, pi);
            if(!val.hasValue) val = e.get!ushort(d, pi);
            if(!val.hasValue) val = e.get!int(d, pi);
            if(!val.hasValue) val = e.get!uint(d, pi);
            if(!val.hasValue) val = e.get!long(d, pi);
            if(!val.hasValue) val = e.get!ulong(d, pi);
            if(!val.hasValue) val = e.get!float(d, pi);
            if(!val.hasValue) val = e.get!double(d, pi);
            if(!val.hasValue) val = e.get!char(d, pi);
            if(!val.hasValue) val = e.get!wchar(d, pi);
            if(!val.hasValue) val = e.get!dchar(d, pi);
            if(!val.hasValue) val = e.get!UUID(d, pi);
            if(!val.hasValue) val = e.get!SysTime(d, pi);
            if(!val.hasValue) val = e.get!DateTime(d, pi);
            if(!val.hasValue) val = e.get!Date(d, pi);
            if(!val.hasValue) val = e.get!Duration(d, pi);
            if(!val.hasValue) val = e.get!string(d, pi);
            if(!val.hasValue)
                val = e.get!Data(d, pi);

            if(val.hasValue)
                pi.set(d, val);
        }
    }

    return d;
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo pi) if(canHandle!T && !is(T : Data)) {
    if(pi.info == typeid(T)) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,pi).get!T();
                return Variant(val);
            case JSON_TYPE.STRING:
                static if(is(T == string))
                    return Variant(j.str);
                else static if(is(T == SysTime) || is(T == DateTime) || is(T == Date))
                    return Variant(T.fromISOString(j.str));
                else static if(is(T == Duration))
                    return Variant(j.integer.hnsecs);
                else static if(is(T == UUID))
                    return Variant(j.str.parseUUID);
                else return Variant();
            case JSON_TYPE.INTEGER:
                static if(isScalarType!T)
                    return Variant(j.integer.as!T);
                else return Variant();
            case JSON_TYPE.UINTEGER:
                static if(isScalarType!T)
                    return Variant(j.uinteger.as!T);
                else return Variant();
            case JSON_TYPE.FLOAT:
                static if(isScalarType!T)
                    return Variant(j.floating.as!T);
                else return Variant();
            case JSON_TYPE.TRUE:
                static if(is(T : bool))
                    return Variant(true);
                else return Variant();
            case JSON_TYPE.FALSE:
                static if(is(T : bool))
                    return Variant(false);
                else return Variant();
            default:
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~pi.name~"\" type mismatching");
        }
    } else return Variant();
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo pi) if(is(T : Data)) {
    if(pi.desc & TypeDesc.Data) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,pi).get!T();
                return Variant(val);
            case JSON_TYPE.OBJECT:
                static if(is(T : Data))
                    return Variant(j.createData());
                else return Variant();
            default:
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~pi.name~"\" type mismatching");
        }
    } else return Variant();
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing json serialization of data and member");

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

    auto dStr = d.json;
    debug(data) writeln(dStr);
    assert(dStr == "{"~
        "\"additional\":\"ble\","~
        "\"boolean\":true,"~
        "\"dataType\":\"flow.core.data.InheritedTestData\","~
        "\"enumeration\":1,"~
        "\"enumerationA\":[1,0],"~
        "\"inner\":{"~
            "\"dataType\":\"flow.core.data.TestData\","~
            "\"integer\":3"~
        "},"~
        "\"innerA\":["~
            "{\"dataType\":\"flow.core.data.TestData\"},"~
            "{\"dataType\":\"flow.core.data.TestData\"}"~
        "],"~
        "\"text\":\"foo\","~
        "\"textA\":[\"foo\",\"bar\"],"~
        "\"uinteger\":5,"~
        "\"uintegerA\":[3,4],"~
        "\"uuid\":\"1bf8eac7-64ee-4cde-aa9e-8877ac2d511d\"}", "could not serialize data");

    auto d2 = parseJSON(dStr).createData().as!InheritedTestData;
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

import std.bitmanip;

private void bin(Variant t, PropertyInfo pi, ref Appender!(ubyte[]) a) {
    import std.stdio;
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

private void bin(T)(T arr, ref Appender!(ubyte[]) a) if(isArray!T && canHandle!(ElementType!T) && !is(T == string)) {
    arr.length.bin(a);
    foreach(e; arr) e.bin(a);
}

private void bin(T)(T val, ref Appender!(ubyte[]) a) if(canHandle!T) {
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

ubyte[] bin(T)(T data) if(is(T: Data)) {
    auto a = appender!(ubyte[]);
    data.bin(a);
    return a.data;
}

class InvalidBinException : Exception {this(string msg){super(msg);}}
private T unbin(T)(ref ubyte[] arr) if(isArray!T && canHandle!(ElementType!T) && !is(T == string)) {
    T uArr;
    auto length = arr.unbin!size_t;
    for(size_t i = 0; i < length; i++)
        uArr ~= arr.unbin!(ElementType!T);

    return uArr;
}

private T unbin(T)(ref ubyte[] arr) if(canHandle!T) {
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
            import std.stdio;
            auto dataType = arr.unbin!string;
            auto val = createData(dataType);

            if(val !is null) {
                foreach(pi; val.properties) {
                    arr.unbin(val, pi.as!PropertyInfo);
                }
                
                return val;
            } else throw new InvalidBinException("unsupported data type \""~dataType~"\"");
        } else return null;
    }
    else {
        auto val = arr[0..T.sizeof].bigEndianToNative!T;
        arr.popFrontN(T.sizeof);
        return val;
    }
}

private void unbin(ref ubyte[] arr, Data d, PropertyInfo pi) {
    import std.stdio;
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

Data unbin(ref ubyte[] arr) {
    return arr.unbin!Data;
}

unittest {
    import std.stdio;
    import std.range;
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

    auto arr = d.bin;    
    debug(data) writeln(arr);
    ubyte[] cArr = [255, 0, 0, 0, 0, 0, 0, 0, 32, 102, 108, 111, 119, 46, 99, 111, 114, 101, 46, 100, 97, 116, 97, 46, 73, 110, 104, 101, 114, 105, 116, 101, 100, 84, 101, 115, 116, 68, 97, 116, 97, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 23, 102, 108, 111, 119, 46, 99, 111, 114, 101, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, 2, 255, 0, 0, 0, 0, 0, 0, 0, 23, 102, 108, 111, 119, 46, 99, 111, 114, 101, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 23, 102, 108, 111, 119, 46, 99, 111, 114, 101, 46, 100, 97, 116, 97, 46, 84, 101, 115, 116, 68, 97, 116, 97, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 241, 136, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 0, 0, 0, 0, 0, 0, 0, 3, 98, 97, 114, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 98, 108, 101, 0, 0, 0, 0, 0, 0, 0, 0, 27, 248, 234, 199, 100, 238, 76, 222, 170, 158, 136, 119, 172, 45, 81, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 102, 111, 111, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 48, 48, 48, 49, 48, 49, 48, 49, 84, 48, 48, 48, 48, 48, 48, 0, 0, 0, 0, 0, 0, 0, 0, 127, 252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    assert(arr == cArr, "could not serialize data");
    
    auto d2 = arr.unbin.as!InheritedTestData;
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