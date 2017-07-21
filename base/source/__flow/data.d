module __flow.data;

import __flow.util;

import std.traits, std.range;
import std.uuid, std.datetime;

private template canHandle(T) {
    enum canHandle = isScalarType!T || is(T : Data) || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || is(T  == string);
}

public PropertyInfo getFieldInfo(T)(string name) if(canHandle!T) {
    PropertyInfo p;
    p._type = typeid(T);
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

public PropertyInfo getArrayInfo(T)(string name) if(canHandle!T) {
    PropertyInfo p;
    p._type = typeid(T);
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

public string fqn(Data d) {return d.dataType;}

public enum TypeFlags {
    Nan,
    Scalar,
    Data,
    UUID,
    SysTime,
    DateTime,
    String
}

/// runtime inforamtions of a data property
public struct PropertyInfo {
	private TypeInfo _type;
    private string _name;
    private bool _array;
    private TypeFlags _flags;

    public @property TypeInfo type() {return this._type;}
    public @property string name() {return this._name;}
    public @property bool array() {return this._array;}
    public @property TypeFlags flags() {return this._flags;}
}

public class DataFactory {
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

public abstract class Data {
    @property shared(PropertyInfo[string]) properties(){return null;}

    public abstract @property string dataType();
}

public mixin template data() {
    static import __flow.util, __flow.data;

    shared static __flow.data.PropertyInfo[string] Properties;
    override @property shared(__flow.data.PropertyInfo[string]) properties(){return Properties;}

    override public @property string dataType() {return __flow.util.fqn!(typeof(this));}
    
    private static __flow.data.Data create() {return new typeof(this);}
    shared static this() {
        DataFactory.register(__flow.util.fqn!(typeof(this)), &create);
    }
}

public mixin template field(T, string name) if (canHandle!T) {
    shared static this() {
        import __flow.data;

        Properties[name] = getFieldInfo!T(name).as!(shared(PropertyInfo));
    }

    mixin(T.stringof~" "~name~";");
}

public mixin template array(T, string name) if (canHandle!T) {
    shared static this() {
        import __flow.data;

        Properties[name] = getArrayInfo!T(name).as!(shared(PropertyInfo));
    }

    mixin(T.stringof~"[] "~name~";");
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
    mixin field!(TestData, "innerA");
    mixin array!(bool, "booleanA");
    mixin array!(long, "integerA");
    mixin array!(ulong, "uintegerA");
    mixin array!(double, "floatingA");
    mixin array!(UUID, "uuidA");
    mixin array!(SysTime, "sysTimeA");
    mixin array!(DateTime, "dateTimeA");
    mixin array!(string, "textA");
}

/// testing static data usage
unittest {
    import std.range;

    auto d = new TestData;
    assert(d !is null, "could not statically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at static creation");
    d.uinteger = 5; assert(d.uinteger == 5, "could not set basic");
    
    assert(d.inner is null, "inner data should be null at init");
    d.inner = new TestData; assert(d.inner !is null, "could not set new data on data.inner");
    d.inner.integer = 3; assert(d.inner.integer == 3, "could not set property of data.inner");
}

/// testing dynamic data usage
unittest {
    auto d = DataFactory.create("__flow.data.TestData").as!TestData;
    assert(d !is null, "could not dynamically create instance of data");
    assert(d.integer is long.init && d.integerA.empty, "data is not initialized correctly at dynamic creation");
}