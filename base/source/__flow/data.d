module __flow.data;

import __flow.util;

import std.traits;
import std.range;
import std.uuid;
import std.datetime;

private template canHandle(T) {
    enum canHandle = isScalarType!T || is(T : Data) || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || is(T == string);
}

string fqn(Data d) {return d.dataType;}

enum TypeFlags {
    Nan,
    Scalar,
    Data,
    UUID,
    SysTime,
    DateTime,
    String
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if (isArray!T && !is(T == string) && canHandle!(ElementType!T)) {
	T value;

	alias value this;

	this(T value) {
		this.value = value;
	}

    Ref!T dup() {
        return new Ref!T(this.value.dup);
    }
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if (canHandle!T) {
	T value;

	alias value this;

	this(T value) {
		this.value = value;
	}

    Ref!T dup() {
        static if(isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || is(T == string)) {
            return new Ref!T(this.value);
        } else {
            return new Ref!T(this.value.dup);
        }
    }
}

class DataFactory {
    private shared static Data function()[string] _reg;

    static void register(string dataType, Data function() creator) {
		_reg[dataType] = creator;
	}

	static bool knows(string dataType) {
		return dataType in _reg ? true : false;
	}

	static Data create(string dataType) {
		if(dataType in _reg)
			return _reg[dataType]();
		else
			return null;
	}
}

/// runtime inforamtions of a data property
struct PropertyInfo {
	private TypeInfo _info;
    private string _type;
    private string _name;
    private bool _array;
    private TypeFlags _flags;

    @property TypeInfo info() {return this._info;}
    @property string type() {return this._type;}
    @property string name() {return this._name;}
    @property bool array() {return this._array;}
    @property TypeFlags flags() {return this._flags;}
}

abstract class Data {
    @property shared(PropertyInfo[string]) properties(){return null;}

    abstract @property string dataType();

	abstract Object get(string name);
	abstract bool set(string name, Object value);

    abstract Data dup();
    abstract protected void dupInternal(Data c);
}

mixin template data() {
    static import __flow.util, __flow.data;
    pragma(msg, "\tdata "~__flow.util.fqn!(typeof(this)));

    shared static __flow.data.PropertyInfo[string] Properties;
    override @property shared(__flow.data.PropertyInfo[string]) properties() {
        return Properties;
    }

    private shared static Object function(typeof(this))[string] _getter;
	private shared static bool function(typeof(this), Object)[string] _setter;
	private shared static void function(typeof(this), typeof(this))[] _dups;
	private shared static bool function(typeof(this), typeof(this))[] _eqs;

    override @property string dataType() {return __flow.util.fqn!(typeof(this));}
    
    private static __flow.data.Data create() {return new typeof(this);}
    shared static this() {
		static if(__flow.util.fqn!(typeof(super)) != "__flow.data.Data")
		foreach(n, i; super.Properties)
			Properties[n] = i;

        DataFactory.register(__flow.util.fqn!(typeof(this)), &create);
    }

    override Object get(string name)
	{
		Object value = null;
		static if(__flow.util.fqn!(typeof(super)) != "__flow.data.Data")
			value = super.get(name);

		if(value is null && name in _getter)
            value = _getter[name](this);

		return value;
	}

	override bool set(string name, Object value) {
		auto set = false;
		static if(__flow.util.fqn!(typeof(super)) != "__flow.data.Data")
			set = super.set(name, value);

		if(!set && name in _setter)
            set = _setter[name](this, value);
        
		return set;
	}

	override typeof(this) dup() {
		auto c = new typeof(this);
		this.dupInternal(c);
		return c;
	}

	override protected void dupInternal(Data c) {
		static if(__flow.util.fqn!(typeof(super)) != "__flow.data.Data")
			super.dupInternal(c);

		auto clone = cast(typeof(this))c;
		foreach(d; _dups)
			d(this, clone);
	}
}

mixin template field(T, string name) if (canHandle!T) {
    pragma(msg, "\t\t"~T.stringof~" "~name);
    shared static this() {
        import __flow.data;

        shared(PropertyInfo) p = TPropertyHelper!(T, name).getFieldInfo().as!(shared(PropertyInfo));
        Properties[name] = p; 

        mixin("_getter[name] = (t) {
            return "~(is(T : Data) ? "t."~name : "new Ref!("~T.stringof~")(t."~name~")")~";
        };");

        mixin("_setter[name] = (t, v) {
            t."~name~" = "~(is(T : Data) ? "v.as!("~T.stringof~")" : "v.as!(Ref!("~T.stringof~")).value")~";
            return true;
        };");

        mixin("_dups ~= (t, c) {
            "~(is(T : Data) ? "if(t."~name~" !is null) c."~name~" = t."~name~".dup" : "c."~name~" = t."~name)~";
        };");
    }

    // field
    mixin(T.stringof~" "~name~";");

}

mixin template array(T, string name) if (canHandle!T) {
    pragma(msg, "\t\t"~T.stringof~"[] "~name);
    shared static this() {
        import __flow.data;

        PropertyInfo p = TPropertyHelper!(T, name).getArrayInfo();
        Properties[name] = p.as!(shared(PropertyInfo));

        mixin("_getter[name] = (t) {
            return new Ref!("~T.stringof~"[])(t."~name~");
        };");

        mixin("_setter[name] = (t, v) {
            t."~name~" = v.as!(Ref!("~T.stringof~"[])).value;
            return true;
        };");

        mixin("_dups ~= (t, c) {
            foreach(e; t."~name~") {
                "~(is(T : Data) ? "c."~name~" ~= e.dup" : "c."~name~" ~= e")~";
            }
        };");
    }

    // field
    mixin(T.stringof~"[] "~name~";");
}

template TPropertyHelper(T, string name) {
    PropertyInfo getFieldInfo() {
        PropertyInfo p;
        p._type = T.stringof;
        p._info = typeid(T);
        p._name = name;
        p._array = false;

        if(isScalarType!T) p._flags = TypeFlags.Scalar;
        else if(is(T : Data)) p._flags = TypeFlags.Data;
        else if(is(T == UUID)) p._flags = TypeFlags.UUID;
        else if(is(T == SysTime)) p._flags = TypeFlags.SysTime;
        else if(is(T == DateTime)) p._flags = TypeFlags.DateTime;
        else if(is(T == string)) p._flags = TypeFlags.String;

        return p;
    }

    PropertyInfo getArrayInfo() {
        PropertyInfo p;
        p._type = T.stringof;
        p._info = typeid(T);
        p._name = name;
        p._array = true;

        if(isScalarType!T) p._flags = TypeFlags.Scalar;
        else if(is(T : Data)) p._flags = TypeFlags.Data;
        else if(is(T == UUID)) p._flags = TypeFlags.UUID;
        else if(is(T == SysTime)) p._flags = TypeFlags.SysTime;
        else if(is(T == DateTime)) p._flags = TypeFlags.DateTime;
        else if(is(T == string)) p._flags = TypeFlags.String;

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

unittest {
    import std.stdio;
    import std.range;
    writeln("testing dynamic data usage");

    auto d = DataFactory.create("__flow.data.InheritedTestData").as!InheritedTestData;
    assert(d !is null, "could not dynamically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at dynamic creation");

    d.set("uinteger", new Ref!ulong(4)); assert(d.uinteger == 4, "could not set basic scalar value");
    assert(d.get("uinteger").as!(Ref!ulong).value == 4, "could not get basic scalar value");
    d.set("text", new Ref!string("foo")); assert(d.text == "foo", "could not set basic string value");
    assert(d.get("text").as!(Ref!string).value == "foo", "could not get basic string value");
    d.set("inner", new TestData); assert(d.inner !is null, "could not set basic data value");
    assert(d.get("inner").as!TestData !is null, "could not get basic data value");
    d.set("integerA", new Ref!(long[])([2L, 3L, 4L])); assert(d.integerA.length == 3 && d.integerA[0] == 2 && d.integerA[1] == 3 && d.integerA[2] == 4, "could not set array scalar value");
    assert(d.get("integerA").as!(Ref!(long[])).value.length == 3, "could not get array scalar value");
    d.set("textA", new Ref!(string[])(["foo", "bar"])); assert(d.textA.length == 2 && d.textA[0] == "foo" && d.textA[1] == "bar", "could not set array string value");
    assert(d.get("textA").as!(Ref!(string[])).value.length == 2, "could not get array string value");
    d.set("innerA", new Ref!(TestData[])([new TestData])); assert(d.innerA.length == 1 && d.innerA[0] !is null, "could not set array data value");
    assert(d.get("innerA").as!(Ref!(TestData[])).value.length == 1, "could not get array data value");
    d.set("additional", new Ref!string("ble")); assert(d.additional == "ble", "could not set second level basic scalar value");
    assert(d.get("additional").as!(Ref!string).value == "ble", "could not get second level basic scalar value");
}

unittest {
    import std.stdio;
    import std.range;
    import std.conv;
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
// 
    assert(d2.uinteger == 5, "could not dup basic scalar value");
    assert(d2.text == "foo", "could not dup basic string value");   
    assert(d2.inner !is null && d2.inner !is d.inner, "could not dup basic data value");
    assert(d2.inner.integer == 3, "could not dup property of basic data value");
    assert(d2.uintegerA.length == 2 && d2.uintegerA[0] == 3 && d2.uintegerA[1] == 4 && d2.uintegerA !is d.uintegerA, "could not dup array scalar value");
    assert(d2.textA.length == 2 && d2.textA[0] == "foo" && d2.textA[1] == "bar", "could not dup array string value");
    assert(d2.innerA.length == 2 && d2.innerA[0] !is null && d2.innerA[1] !is null && d2.innerA[0] !is d2.innerA[1] && d2.innerA[0] !is d.innerA[0], "could not set array data value");

    assert(d2.additional == "ble", "could not dup basic scalar value");
}