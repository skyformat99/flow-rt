module flow.base.data;

import flow.base.util;

import std.traits;
import std.variant;
import std.range;
import std.uuid;
import std.datetime;
import std.json;

template canHandle(T) {
    enum canHandle =
        isScalarType!T ||
        is(T == UUID) ||
        is(T == SysTime) ||
        is(T == DateTime) ||
        is(T == Date) ||
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
}

abstract class Data {
    @property shared(PropertyInfo[string]) properties(){return null;}

    abstract @property string dataType();
}

mixin template data() {
    static import __flowutil = flow.base.util, __flowdata = flow.base.data;
    pragma(msg, "\tdata "~__flowutil.fqn!(typeof(this)));

    shared static __flowdata.PropertyInfo[string] Properties;
    override @property shared(__flowdata.PropertyInfo[string]) properties() {
        return Properties;
    }

    override @property string dataType() {return __flowutil.fqn!(typeof(this));}
    
    shared static this() {
		static if(__flowutil.fqn!(typeof(super)) != "flow.base.data.Data")
            foreach(n, i; super.Properties)
                Properties[n] = i;
    }
}

mixin template signal(T = void)
    if (is(T == void) || canHandle!T) {   
    static import __flowdata = flow.base.data;
    mixin __flowdata.data;

    static if(!is(T == void)) {
        mixin __flowdata.field!(ulong, "seq");
        mixin __flowdata.field!(T, "data");
    }
}

mixin template field(T, string name) if (canHandle!T) {
    pragma(msg, "\t\t"~T.stringof~" "~name);
    shared static this() {
        import flow.base.util, flow.base.data;

        import std.variant;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ? "t."~name~".as!Data" : "t."~name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : T.stringof)~")) {
                t."~name~" = "~(is(T : Data) ? "v.get!Data().as!"~T.stringof : "v.get!("~T.stringof~")")~";
                return true;
            } else return false;
        };");

        Properties[name] = TPropertyHelper!(T, name).getFieldInfo(getter, setter).as!(shared(PropertyInfo));
    }

    // field
    mixin(T.stringof~" "~name~";");
}

mixin template array(T, string name) if (canHandle!T) {
    pragma(msg, "\t\t"~T.stringof~"[] "~name);
    shared static this() {
        import flow.base.util, flow.base.data;

        import std.variant;

        mixin("Variant function(Data) getter = (d) {
            auto t = d.as!(typeof(this));
            return Variant("~(is(T : Data) ? "t."~name~".as!(Data[])" : "t."~name)~");
        };");

        mixin("bool function(Data, Variant) setter = (d, v) {
            auto t = d.as!(typeof(this));
            if(v.convertsTo!("~(is(T : Data) ? "Data" : T.stringof)~"[])) {
                t."~name~" = "~(is(T : Data) ? "v.get!(Data[])().as!("~T.stringof~"[])" : "v.get!("~T.stringof~"[])")~";
                return true;
            } else return false;
        };");

        Properties[name] = TPropertyHelper!(T, name).getArrayInfo(getter, setter).as!(shared(PropertyInfo));
    }
    
    // field
    mixin(T.stringof~"[] "~name~";");
}

template TPropertyHelper(T, string name) {
    PropertyInfo getFieldInfo(Variant function(Data) getter, bool function(Data, Variant) setter) {
        PropertyInfo p;
        p._type = T.stringof;
        p._info = typeid(T);
        p._name = name;
        p._array = false;
        p._getter = getter;
        p._setter = setter;

        if(isScalarType!T) p._desc = TypeDesc.Scalar;
        else if(is(T : Data)) p._desc = TypeDesc.Data;
        else if(is(T == UUID)) p._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) p._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) p._desc = TypeDesc.DateTime;
        else if(is(T == Date)) p._desc = TypeDesc.Date;
        else if(is(T == string)) p._desc = TypeDesc.String;

        return p;
    }

    PropertyInfo getArrayInfo(Variant function(Data) getter, bool function(Data, Variant) setter) {
        PropertyInfo p;
        p._type = T.stringof;
        p._info = typeid(T);
        p._name = name;
        p._array = true;
        p._getter = getter;
        p._setter = setter;

        if(isScalarType!T) p._desc = TypeDesc.Scalar;
        else if(is(T : Data)) p._desc = TypeDesc.Data;
        else if(is(T == UUID)) p._desc = TypeDesc.UUID;
        else if(is(T == SysTime)) p._desc = TypeDesc.SysTime;
        else if(is(T == DateTime)) p._desc = TypeDesc.DateTime;
        else if(is(T == Date)) p._desc = TypeDesc.Date;
        else if(is(T == string)) p._desc = TypeDesc.String;

        return p;
    }
}

version (unittest) class TestData : Data {
    mixin data;

    // testing basic fields
    mixin field!(TestData, "inner");
    mixin field!(bool, "boolean");
    mixin field!(long, "integer");
    mixin field!(ulong, "uinteger");
    mixin field!(double, "floating");
    mixin field!(UUID, "uuid");
    mixin field!(SysTime, "sysTime");
    mixin field!(DateTime, "dateTime");
    mixin field!(string, "text");

    // testing array fields
    mixin array!(TestData, "innerA");
    mixin array!(bool, "booleanA");
    mixin array!(long, "integerA");
    mixin array!(ulong, "uintegerA");
    mixin array!(double, "floatingA");
    mixin array!(UUID, "uuidA");
    mixin array!(SysTime, "sysTimeA");
    mixin array!(DateTime, "dateTimeA");
    mixin array!(string, "textA");

    // testing for module name conflicts
    mixin field!(string, "flow");
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
    
    d.uinteger = 5; assert(d.uinteger == 5, "could not set basic scalar value");
    d.text = "foo"; assert(d.text == "foo", "could not set basic string value");    
    d.inner = new TestData; assert(d.inner !is null, "could not set basic data value");
    d.inner.integer = 3; assert(d.inner.integer == 3, "could not set property of basic data value");
    d.uintegerA ~= 3; d.uintegerA ~= 4; assert(d.uintegerA.length == 2 && d.uintegerA[0] == 3 && d.uintegerA[1] == 4, "could not set array scalar value");
    d.uintegerA = [1]; assert(d.uintegerA.length == 1 && d.uintegerA[0] == 1, "could not set array scalar value");
    d.textA ~= "foo"; d.textA ~= "bar"; assert(d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    d.textA = ["bla"]; assert(d.textA.length == 1 && d.textA[0] == "bla", "could not set array string value");
    d.innerA ~= new TestData; d.innerA ~= new TestData; assert(d.innerA.length == 2 && d.innerA[0] !is null && d.innerA[1] !is null && d.innerA[0] !is d.innerA[1], "could not set array data value");
    d.innerA = [new TestData]; assert(d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    d.additional = "ble"; assert(d.additional == "ble", "could not set second level basic scalar");
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

T get(T)(Data d, string name) if((canHandle!T && !is(T : Data)) || (isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data))) {
    return d.get(name).get!T();
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

bool set(T)(Data d, string name, T val) if((canHandle!T && !is(T : Data)) || (isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data))) {
    return d.set(name, Variant(val));
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing dynamic data usage");

    auto d = "flow.base.data.InheritedTestData".createData().as!InheritedTestData;
    assert(d !is null, "could not dynamically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at dynamic creation");

    assert(d.set("uinteger", 4) && d.uinteger == 4, "could not set basic scalar value");
    assert(d.get!ulong("uinteger") == 4, "could not get basic scalar value");
    
    assert(d.set("text", "foo") && d.text == "foo", "could not set basic string value");
    assert(d.get!string("text") == "foo", "could not get basic string value");
    
    assert(d.set("inner", new TestData) && d.inner !is null, "could not set basic data value");
    assert(d.get!TestData("inner") !is null, "could not get basic data value");
    assert(d.set("inner", null.as!TestData) && d.inner is null, "could not set basic data value");
    assert(d.get!TestData("inner") is null, "could not get basic data value");
    
    assert(d.set("integerA", [2L, 3L, 4L]) && d.integerA.length == 3 && d.integerA[0] == 2 && d.integerA[1] == 3 && d.integerA[2] == 4, "could not set array scalar value");
    assert(d.get!(long[])("integerA").length == 3, "could not get array scalar value");
    
    assert(d.set("textA", ["foo", "bar"]) && d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    assert(d.get!(string[])("textA").length == 2, "could not get array string value");
    
    assert(d.set("innerA", [new TestData]) && d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    assert(d.get!(TestData[])("innerA").length == 1, "could not get array data value");
    
    assert(d.set("additional", "ble") && d.additional == "ble", "could not set second level basic scalar value");
    assert(d.get!string("additional") == "ble", "could not get second level basic scalar value");
}

T[] dup(T)(T[] arr) if(is(T : Data)) {
    T[] cArr;
    foreach(e; arr) cArr ~= e.dup;

    return cArr;
}

T[] dup(T)(T[] arr) if(canHandle!T && !is(T : Data)) {
    T[] cArr;
    foreach(e; arr) cArr ~= e;

    return cArr;
}

private Variant dup(Variant t, PropertyInfo p) {
    import std.stdio;
    if(p.array) {
        if(p.desc == TypeDesc.Scalar && p.info == typeid(bool))
            return Variant(t.get!(bool[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(byte))
            return Variant(t.get!(byte[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ubyte))
            return Variant(t.get!(ubyte[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(short))
            return Variant(t.get!(short[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ushort))
            return Variant(t.get!(ushort[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(int))
            return Variant(t.get!(int[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(uint))
            return Variant(t.get!(uint[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(long))
            return Variant(t.get!(long[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ulong))
            return Variant(t.get!(ulong[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(float))
            return Variant(t.get!(float[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(double))
            return Variant(t.get!(double[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(char))
            return Variant(t.get!(char[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(wchar))
            return Variant(t.get!(wchar[]).dup);
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(dchar))
            return Variant(t.get!(dchar[]).dup);
        else if(p.desc == TypeDesc.UUID)
            return Variant(t.get!(UUID[]).dup);
        else if(p.desc == TypeDesc.SysTime)
            return Variant(t.get!(SysTime[]).dup);
        else if(p.desc == TypeDesc.DateTime)
            return Variant(t.get!(DateTime[]).dup);
        else if(p.desc == TypeDesc.Date)
            return Variant(t.get!(Date[]).dup);
        else if(p.desc == TypeDesc.String)
            return Variant(t.get!(string[]).dup);
        else if(p.desc == TypeDesc.Data)
            return Variant(t.get!(Data[]).dup);
        else assert(false, "this is an impossible situation");
    } else {
        if(p.desc == TypeDesc.Data)
            return Variant(t.get!(Data).dup);
        else return t;
    }
}

Data dup(Data t) {
    import std.stdio;
    Data c;
    if(t !is null) {
        c = Object.factory(t.dataType).as!Data;

        foreach(prop; t.properties) {
            auto p = prop.as!PropertyInfo;
            auto val = p.get(t);
            p.set(c, val.dup(p));
        }
    }

    return c;
}

unittest {
    import std.stdio;
    import std.range;
    writeln("testing dup of data and member");

    auto d = new InheritedTestData;
    d.uinteger = 5;
    d.text = "foo";
    d.inner = new TestData;
    d.inner.integer = 3;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.additional = "ble";

    auto d2 = d.dup().as!InheritedTestData;
 
    assert(d2.uinteger == 5, "could not dup basic scalar value");
    assert(d2.text == "foo", "could not dup basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not dup basic data value");
    assert(d2.inner.integer == 3, "could not dup property of basic data value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not dup array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not dup array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");

    assert(d2.additional == "ble", "could not dup basic scalar value");
}

private JSONValue json(Variant t, PropertyInfo p) {
    import std.stdio;
    if(p.array) {
        if(p.desc == TypeDesc.Scalar && p.info == typeid(bool))
            return t.get!(bool[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(byte))
            return t.get!(byte[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ubyte))
            return t.get!(ubyte[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(short))
            return t.get!(short[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ushort))
            return t.get!(ushort[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(int))
            return t.get!(int[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(uint))
            return t.get!(uint[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(long))
            return t.get!(long[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ulong))
            return t.get!(ulong[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(float))
            return t.get!(float[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(double))
            return t.get!(double[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(char))
            return t.get!(char[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(wchar))
            return t.get!(wchar[]).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(dchar))
            return t.get!(dchar[]).json;
        else if(p.desc == TypeDesc.UUID)
            return t.get!(UUID[]).json;
        else if(p.desc == TypeDesc.SysTime)
            return t.get!(SysTime[]).json;
        else if(p.desc == TypeDesc.DateTime)
            return t.get!(DateTime[]).json;
        else if(p.desc == TypeDesc.Date)
            return t.get!(Date[]).json;
        else if(p.desc == TypeDesc.String)
            return t.get!(string[]).json;
        else if(p.desc == TypeDesc.Data)
            return t.get!(Data[]).json;
        else assert(false, "this is an impossible situation");
    } else {
        if(p.desc == TypeDesc.Scalar && p.info == typeid(bool))
            return t.get!(bool).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(byte))
            return t.get!(byte).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ubyte))
            return t.get!(ubyte).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(short))
            return t.get!(short).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ushort))
            return t.get!(ushort).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(int))
            return t.get!(int).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(uint))
            return t.get!(uint).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(long))
            return t.get!(long).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(ulong))
            return t.get!(ulong).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(float))
            return t.get!(float).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(double))
            return t.get!(double).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(char))
            return t.get!(char).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(wchar))
            return t.get!(wchar).json;
        else if(p.desc == TypeDesc.Scalar && p.info == typeid(dchar))
            return t.get!(dchar).json;
        else if(p.desc == TypeDesc.UUID)
            return t.get!(UUID).json;
        else if(p.desc == TypeDesc.SysTime)
            return t.get!(SysTime).json;
        else if(p.desc == TypeDesc.DateTime)
            return t.get!(DateTime).json;
        else if(p.desc == TypeDesc.Date)
            return t.get!(Date).json;
        else if(p.desc == TypeDesc.String)
            return t.get!(string).json;
        else if(p.desc == TypeDesc.Data)
            return t.get!(Data).json;
        else assert(false, "this is an impossible situation");
    }
}

private JSONValue json(T)(T arr) if(isArray!T && is(ElementType!T : Data) || is(ElementType!T == UUID) || is(ElementType!T == SysTime) || is(ElementType!T == DateTime) || is(ElementType!T == Date)) {
    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= e.json;

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue json(T)(T arr) if(isArray!T && canHandle!(ElementType!T) && !is(T == string) && !is(ElementType!T : Data) && !is(ElementType!T == UUID) && !is(ElementType!T == SysTime) && !is(ElementType!T == DateTime) && !is(ElementType!T == Date)) {
    if(!arr.empty) {
        JSONValue[] cArr;
        foreach(e; arr) cArr ~= JSONValue(e);

        return JSONValue(cArr);
    } else return JSONValue(null);
}

private JSONValue json(T)(T val) if(canHandle!T && !is(T : Data) && !is(T == float) && !is(T == double) && !is(T == UUID) && !is(T == SysTime) && !is(T == DateTime) && !is(T == Date)) {
    return val is T.init ? JSONValue(null) : JSONValue(val);
}

private JSONValue json(T)(T val) if(is(T == float) || is(T == double)) {
    import std.math;
    return val is T.init || isNaN(val) ? JSONValue(null) : JSONValue(val);
}

private JSONValue json(T)(T val) if(is(T == UUID)) {
    return val is T.init ? JSONValue(null) : JSONValue(val.toString());
}

private JSONValue json(T)(T val) if(is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
    return val is T.init ? JSONValue(null) : JSONValue(val.toISOExtString());
}

JSONValue json(T)(T t) if(is(T : Data)) {
    import std.stdio;
    JSONValue c;
    if(t !is null) {
        c = JSONValue(["dataType" : JSONValue(t.dataType)]);

        foreach(prop; t.properties) {
            auto p = prop.as!PropertyInfo;
            auto val = p.get(t);
            auto j = val.json(p);
            if(!j.isNull) c.object[p.name] = j;
        }
    }

    return c;
}

class InvalidJsonException : Exception {this(string msg){super(msg);}}
Data createData(JSONValue j) {
    auto dt = j["dataType"].str;
    if(dt == string.init)
        throw new InvalidJsonException("json object has no dataType");

    auto d = dt.createData();
    foreach(string name, e; j) {
        if(name != "dataType") {
            if(name !in d.properties)
                throw new InvalidJsonException("\""~d.dataType~"\" contains no property named \""~name~"\"");
        
            auto p = d.properties[name].as!PropertyInfo;
            Variant val;
            if(!val.hasValue) val = e.get!bool(d, p);
            if(!val.hasValue) val = e.get!byte(d, p);
            if(!val.hasValue) val = e.get!ubyte(d, p);
            if(!val.hasValue) val = e.get!short(d, p);
            if(!val.hasValue) val = e.get!ushort(d, p);
            if(!val.hasValue) val = e.get!int(d, p);
            if(!val.hasValue) val = e.get!uint(d, p);
            if(!val.hasValue) val = e.get!long(d, p);
            if(!val.hasValue) val = e.get!ulong(d, p);
            if(!val.hasValue) val = e.get!float(d, p);
            if(!val.hasValue) val = e.get!double(d, p);
            if(!val.hasValue) val = e.get!char(d, p);
            if(!val.hasValue) val = e.get!wchar(d, p);
            if(!val.hasValue) val = e.get!dchar(d, p);
            if(!val.hasValue) val = e.get!UUID(d, p);
            if(!val.hasValue) val = e.get!SysTime(d, p);
            if(!val.hasValue) val = e.get!DateTime(d, p);
            if(!val.hasValue) val = e.get!Date(d, p);
            if(!val.hasValue) val = e.get!string(d, p);
            if(!val.hasValue)
                val = e.get!Data(d, p);

            if(val.hasValue)
                p.set(d, val);
        }
    }

    return d;
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo p) if(canHandle!T && !is(T : Data)) {
    if(p.info == typeid(T)) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,p).get!T();
                return Variant(val);
            case JSON_TYPE.STRING:
                static if(is(T == string))
                    return Variant(j.str);
                else static if(is(T == SysTime) || is(T == DateTime) || is(T == Date))
                    return Variant(T.fromISOString(j.str));
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
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~p.name~"\" type mismatching");
        }
    } else return Variant();
}

private Variant get(T)(JSONValue j, Data d, PropertyInfo p) if(is(T : Data)) {
    if(p.desc & TypeDesc.Data) {
        switch(j.type) {
            case JSON_TYPE.ARRAY:
                    T[] val;
                    foreach(size_t i, e; j)
                        val ~= e.get!T(d ,p).get!T();
                return Variant(val);
            case JSON_TYPE.OBJECT:
                static if(is(T : Data))
                    return Variant(j.createData());
                else return Variant();
            default:
                throw new InvalidJsonException("\""~d.dataType~"\" property \""~p.name~"\" type mismatching");
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
    d.inner = new TestData;
    d.inner.integer = 3;
    d.uintegerA = [3, 4];
    d.textA = ["foo", "bar"];
    d.innerA = [new TestData, new TestData];
    d.additional = "ble";

    auto dStr = d.json.toString();
    assert(dStr == "{"~
        "\"additional\":\"ble\","~
        "\"boolean\":true,"~
        "\"dataType\":\"flow.base.data.InheritedTestData\""~
        ",\"inner\":{"~
            "\"dataType\":\"flow.base.data.TestData\","~
            "\"integer\":3"~
        "},"~
        "\"innerA\":["~
            "{\"dataType\":\"flow.base.data.TestData\"},"~
            "{\"dataType\":\"flow.base.data.TestData\"}"~
        "],"~
        "\"text\":\"foo\","~
        "\"textA\":[\"foo\",\"bar\"],"~
        "\"uinteger\":5,"~
        "\"uintegerA\":[3,4]}", "could not serialize data");

    auto d2 = parseJSON(dStr).createData().as!InheritedTestData;
    assert(d2 !is null, "could not deserialize data");
    assert(d2.boolean, "could not deserialize basic scalar value");
    assert(d2.uinteger == 5, "could not deserialize basic scalar value");
    assert(d2.text == "foo", "could not deserialize basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not deserialize basic data value");
    assert(d2.inner.integer == 3, "could not deserialize property of basic data value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not deserialize array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not deserialize array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");

    assert(d2.additional == "ble", "could not deserialize basic scalar value");
}