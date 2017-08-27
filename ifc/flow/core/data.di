// D import file generated from './flow/core/data.d'
module flow.core.data;
import flow.core.util;
import std.traits;
import std.variant;
import std.range;
import std.uuid;
import std.datetime;
import std.json;
enum canHandle(T) = is(T == bool) || is(T == byte) || is(T == ubyte) || is(T == short) || is(T == ushort) || is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == float) || is(T == double) || is(T == char) || is(T == wchar) || is(T == dchar) || is(T == enum) && is(OriginalType!T == bool) || is(T == enum) && is(OriginalType!T == byte) || is(T == enum) && is(OriginalType!T == ubyte) || is(T == enum) && is(OriginalType!T == short) || is(T == enum) && is(OriginalType!T == ushort) || is(T == enum) && is(OriginalType!T == int) || is(T == enum) && is(OriginalType!T == uint) || is(T == enum) && is(OriginalType!T == long) || is(T == enum) && is(OriginalType!T == ulong) || is(T == enum) && is(OriginalType!T == float) || is(T == enum) && is(OriginalType!T == double) || is(T == enum) && is(OriginalType!T == char) || is(T == enum) && is(OriginalType!T == wchar) || is(T == enum) && is(OriginalType!T == dchar) || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == Duration) || is(T == string) || is(T : Data);
string fqn(Data d);
enum TypeDesc 
{
	Scalar,
	UUID,
	SysTime,
	DateTime,
	Date,
	Duration,
	String,
	Data,
}
class TypeMismatchException : Exception
{
	this()
	{
		super(string.init);
	}
}
struct PropertyInfo
{
	private TypeInfo _info;
	private string _type;
	private string _name;
	private bool _array;
	private TypeDesc _desc;
	private Variant function(Data) _getter;
	private bool function(Data, Variant) _setter;
	private bool function(Data, Data) _equals;
	@property TypeInfo info();
	@property string type();
	@property string name();
	@property bool array();
	@property TypeDesc desc();
	Variant get(Data d);
	bool set(Data d, Variant v);
	bool equal(Data a, Data b);
}
abstract class Data
{
	@property shared(PropertyInfo[string]) properties();
	abstract @property string dataType();
	override bool opEquals(Object o);
	@property Data clone();
}
template data()
{
	static import __flowutil = flow.core.util;
	static import __flowdata = flow.core.data;
	debug (data)
	{
		pragma (msg, "\x09data " ~ __flowutil.fqn!(typeof(this)));
	}
	static shared __flowdata.PropertyInfo[string] Properties;
	override @property shared(__flowdata.PropertyInfo[string]) properties()
	{
		return Properties;
	}
	override @property string dataType()
	{
		return __flowutil.fqn!(typeof(this));
	}
	shared static this()
	{
		static if (__flowutil.fqn!(typeof(super)) != "flow.core.data.Data")
		{
			foreach (n, i; super.Properties)
			{
				Properties[n] = i;
			}
		}

	}
	override @property typeof(this) clone()
	{
		return cast(typeof(this))super.clone;
	}
}
template field(T, string name) if (canHandle!T)
{
	debug (data)
	{
		pragma (msg, "\x09\x09" ~ T.stringof ~ " " ~ name);
	}
	shared static this()
	{
		import flow.core.util;
		import flow.core.data;
		import std.variant;
		import std.traits;
		mixin("Variant function(Data) getter = (d) {\x0a            auto t = d.as!(typeof(this));\x0a            return Variant(" ~ (is(T : Data) ? "t." ~ name ~ ".as!Data" : "cast(" ~ OriginalType!T.stringof ~ ")t." ~ name) ~ ");\x0a        };");
		mixin("bool function(Data, Variant) setter = (d, v) {\x0a            auto t = d.as!(typeof(this));\x0a            if(v.convertsTo!(" ~ (is(T : Data) ? "Data" : OriginalType!T.stringof) ~ ")) {\x0a                t." ~ name ~ " = cast(" ~ T.stringof ~ ")" ~ (is(T : Data) ? "v.get!Data().as!" ~ T.stringof : "v.get!(" ~ OriginalType!T.stringof ~ ")") ~ ";\x0a                return true;\x0a            } else return false;\x0a        };");
		mixin("bool function(Data, Data) equals = (a, b) {\x0a            static if(is(T == float) || is(T == double)) {\x0a                import std.math;\x0a                return a.as!(typeof(this))." ~ name ~ ".isIdentical(b.as!(typeof(this))." ~ name ~ ");\x0a            } else\x0a                return a.as!(typeof(this))." ~ name ~ " == b.as!(typeof(this))." ~ name ~ ";\x0a        };");
		Properties[name] = TPropertyHelper!(T, name).getFieldInfo(getter, setter, equals).as!(shared(PropertyInfo));
	}
	mixin(T.stringof ~ " " ~ name ~ ";");
}
template array(T, string name) if (canHandle!T)
{
	debug (data)
	{
		pragma (msg, "\x09\x09" ~ T.stringof ~ "[] " ~ name);
	}
	shared static this()
	{
		import flow.core.util;
		import flow.core.data;
		import std.variant;
		import std.traits;
		mixin("Variant function(Data) getter = (d) {\x0a            auto t = d.as!(typeof(this));\x0a            return Variant(" ~ (is(T : Data) ? "t." ~ name ~ ".as!(Data[])" : "cast(" ~ OriginalType!T.stringof ~ "[])t." ~ name) ~ ");\x0a        };");
		mixin("bool function(Data, Variant) setter = (d, v) {\x0a            auto t = d.as!(typeof(this));\x0a            if(v.convertsTo!(" ~ (is(T : Data) ? "Data" : OriginalType!T.stringof) ~ "[])) {\x0a                t." ~ name ~ " = cast(" ~ T.stringof ~ "[])" ~ (is(T : Data) ? "v.get!(Data[])().as!(" ~ T.stringof ~ "[])" : "v.get!(" ~ OriginalType!T.stringof ~ "[])") ~ ";\x0a                return true;\x0a            } else return false;\x0a        };");
		mixin("bool function(Data, Data) equals = (a, b) {            \x0a            import std.algorithm.comparison;\x0a            static if(is(T == float) || is(T == double)) {\x0a                import std.math;\x0a                return a.as!(typeof(this))." ~ name ~ ".equal!((x, y) => x.isIdentical(y))(b.as!(typeof(this))." ~ name ~ ");\x0a            } else {\x0a                return a.as!(typeof(this))." ~ name ~ ".equal(b.as!(typeof(this))." ~ name ~ ");\x0a            }\x0a        };");
		Properties[name] = TPropertyHelper!(T, name).getArrayInfo(getter, setter, equals).as!(shared(PropertyInfo));
	}
	mixin(T.stringof ~ "[] " ~ name ~ ";");
}
template TPropertyHelper(T, string name)
{
	PropertyInfo getFieldInfo(Variant function(Data) getter, bool function(Data, Variant) setter, bool function(Data, Data) equals)
	{
		PropertyInfo pi;
		static if (isScalarType!T)
		{
			pi._type = OriginalType!T.stringof;
			pi._info = typeid(OriginalType!T);
		}
		else
		{
			pi._type = T.stringof;
			pi._info = typeid(T);
		}
		pi._name = name;
		pi._array = false;
		pi._getter = getter;
		pi._setter = setter;
		pi._equals = equals;
		if (isScalarType!T)
			pi._desc = TypeDesc.Scalar;
		else if (is(T : Data))
			pi._desc = TypeDesc.Data;
		else if (is(T == UUID))
			pi._desc = TypeDesc.UUID;
		else if (is(T == SysTime))
			pi._desc = TypeDesc.SysTime;
		else if (is(T == DateTime))
			pi._desc = TypeDesc.DateTime;
		else if (is(T == Date))
			pi._desc = TypeDesc.Date;
		else if (is(T == Duration))
			pi._desc = TypeDesc.Duration;
		else if (is(T == string))
			pi._desc = TypeDesc.String;
		return pi;
	}
	PropertyInfo getArrayInfo(Variant function(Data) getter, bool function(Data, Variant) setter, bool function(Data, Data) equals)
	{
		PropertyInfo pi;
		static if (isScalarType!T)
		{
			pi._type = OriginalType!T.stringof;
			pi._info = typeid(OriginalType!T);
		}
		else
		{
			pi._type = T.stringof;
			pi._info = typeid(T);
		}
		pi._name = name;
		pi._array = true;
		pi._getter = getter;
		pi._setter = setter;
		pi._equals = equals;
		if (isScalarType!T)
			pi._desc = TypeDesc.Scalar;
		else if (is(T : Data))
			pi._desc = TypeDesc.Data;
		else if (is(T == UUID))
			pi._desc = TypeDesc.UUID;
		else if (is(T == SysTime))
			pi._desc = TypeDesc.SysTime;
		else if (is(T == DateTime))
			pi._desc = TypeDesc.DateTime;
		else if (is(T == Date))
			pi._desc = TypeDesc.Date;
		else if (is(T == Duration))
			pi._desc = TypeDesc.Duration;
		else if (is(T == string))
			pi._desc = TypeDesc.String;
		return pi;
	}
}
version (unittest)
{
	enum TestEnum 
	{
		Foo,
		Bar,
	}
}
version (unittest)
{
	class TestData : Data
	{
		mixin data!();
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
		mixin field!(string, "flow");
		mixin field!(double, "nan");
		mixin array!(double, "nanA");
	}
}
version (unittest)
{
	class InheritedTestData : TestData
	{
		mixin data!();
		mixin field!(string, "additional");
	}
}
Data createData(string name);
class PropertyNotExistingException : Exception
{
	this()
	{
		super(string.init);
	}
}
private Variant get(Data d, string name);
T get(T)(Data d, string name) if (is(T : Data))
{
	return d.get(name).get!Data().as!T;
}
T get(T)(Data d, string name) if (isArray!T && is(ElementType!T : Data))
{
	return d.get(name).get!(Data[])().as!T;
}
T get(T)(Data d, string name) if (canHandle!T && !is(T : Data))
{
	return cast(T)d.get(name).get!(OriginalType!T)();
}
T get(T)(Data d, string name) if (!is(T == string) && isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data))
{
	return cast(T)d.get(name).get!(OriginalType!(ElementType!T)[])();
}
private bool set(Data d, string name, Variant val);
bool set(T)(Data d, string name, T val) if (is(T : Data))
{
	return d.set(name, Variant(val.as!Data));
}
bool set(T)(Data d, string name, T val) if (isArray!T && is(ElementType!T : Data))
{
	return d.set(name, Variant(val.as!(Data[])));
}
bool set(T)(Data d, string name, T val) if (canHandle!T && !is(T : Data))
{
	return d.set(name, Variant(cast(OriginalType!T)val));
}
bool set(T)(Data d, string name, T val) if (!is(T == string) && isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data))
{
	return d.set(name, Variant(cast(OriginalType!(ElementType!T)[])val));
}
T clone(T)(T arr) if (isArray!T && is(ElementType!T : Data))
{
	T cArr;
	foreach (e; arr)
	{
		cArr ~= cast(ElementType!T)e.clone;
	}
	return cArr;
}
T clone(T)(T arr) if (isArray!T && canHandle!(ElementType!T) && !is(ElementType!T : Data))
{
	T cArr;
	foreach (e; arr)
	{
		cArr ~= e;
	}
	return cArr;
}
private Variant clone(Variant t, PropertyInfo pi);
private JSONValue jsonValue(Variant t, PropertyInfo pi);
private JSONValue jsonValue(T)(T arr) if (isArray!T && (is(ElementType!T : Data) || is(ElementType!T == UUID) || is(ElementType!T == SysTime) || is(ElementType!T == DateTime) || is(ElementType!T == Date) || is(ElementType!T == Duration)))
{
	if (!arr.empty)
	{
		JSONValue[] cArr;
		foreach (e; arr)
		{
			cArr ~= e.jsonValue;
		}
		return JSONValue(cArr);
	}
	else
		return JSONValue(null);
}
private JSONValue jsonValue(T)(T arr) if (isArray!T && canHandle!(ElementType!T) && !is(T == string) && !is(ElementType!T : Data) && !is(ElementType!T == UUID) && !is(ElementType!T == SysTime) && !is(ElementType!T == DateTime) && !is(ElementType!T == Date) && !is(ElementType!T == Duration))
{
	if (!arr.empty)
	{
		JSONValue[] cArr;
		foreach (e; arr)
		{
			cArr ~= JSONValue(e);
		}
		return JSONValue(cArr);
	}
	else
		return JSONValue(null);
}
private JSONValue jsonValue(T)(T val) if (canHandle!T && !is(T : Data) && !is(T == float) && !is(T == double) && !is(T == UUID) && !is(T == SysTime) && !is(T == DateTime) && !is(T == Date) && !is(T == Duration))
{
	return val is T.init ? JSONValue(null) : JSONValue(val);
}
private JSONValue jsonValue(T)(T val) if (is(T == float) || is(T == double))
{
	import std.math;
	return val is T.init || isNaN(val) ? JSONValue(null) : JSONValue(val);
}
private JSONValue jsonValue(T)(T val) if (is(T == UUID))
{
	return val is T.init ? JSONValue(null) : JSONValue(val.toString());
}
private JSONValue jsonValue(T)(T val) if (is(T == SysTime) || is(T == DateTime) || is(T == Date))
{
	return val is T.init ? JSONValue(null) : JSONValue(val.toISOExtString());
}
private JSONValue jsonValue(T)(T val) if (is(T == Duration))
{
	return val is T.init ? JSONValue(null) : JSONValue(val.total!"hnsecs");
}
private JSONValue jsonValue(T)(T data) if (is(T : Data))
{
	JSONValue c;
	if (data !is null)
	{
		c = JSONValue(["dataType":JSONValue(data.dataType)]);
		foreach (prop; data.properties)
		{
			auto pi = prop.as!PropertyInfo;
			auto val = pi.get(data);
			auto j = val.jsonValue(pi);
			if (!j.isNull)
				c.object[pi.name] = j;
		}
	}
	return c;
}
enum JsonSerializer 
{
	StdJson,
}
string json(T)(T data, bool pretty = false, JsonSerializer serializer = JsonSerializer.StdJson)
{
	switch (serializer)
	{
		case JsonSerializer.StdJson:
		{
			return pretty ? data.jsonValue.toPrettyString : data.jsonValue.toString;
		}
		default:
		{
			throw new NotImplementedError;
		}
	}
}
class InvalidJsonException : Exception
{
	this(string msg)
	{
		super(msg);
	}
}
Data createDataFromJson(string str, JsonSerializer serializer = JsonSerializer.StdJson);
private Data createData(JSONValue j);
private Variant get(T)(JSONValue j, Data d, PropertyInfo pi) if (canHandle!T && !is(T : Data))
{
	if (pi.info == typeid(T))
	{
		switch (j.type)
		{
			case JSON_TYPE.ARRAY:
			{
				T[] val;
				foreach (size_t i, e; j)
				{
					val ~= e.get!T(d, pi).get!T();
				}
				return Variant(val);
			}
			case JSON_TYPE.STRING:
			{
				static if (is(T == string))
				{
					return Variant(j.str);
				}
				else
				{
					static if (is(T == SysTime) || is(T == DateTime) || is(T == Date))
					{
						return Variant(T.fromISOString(j.str));
					}
					else
					{
						static if (is(T == Duration))
						{
							return Variant(j.integer.hnsecs);
						}
						else
						{
							static if (is(T == UUID))
							{
								return Variant(j.str.parseUUID);
							}
							else
							{
								return Variant();
							}
						}
					}
				}
			}
			case JSON_TYPE.INTEGER:
			{
				static if (isScalarType!T)
				{
					return Variant(j.integer.as!T);
				}
				else
				{
					return Variant();
				}
			}
			case JSON_TYPE.UINTEGER:
			{
				static if (isScalarType!T)
				{
					return Variant(j.uinteger.as!T);
				}
				else
				{
					return Variant();
				}
			}
			case JSON_TYPE.FLOAT:
			{
				static if (isScalarType!T)
				{
					return Variant(j.floating.as!T);
				}
				else
				{
					return Variant();
				}
			}
			case JSON_TYPE.TRUE:
			{
				static if (is(T : bool))
				{
					return Variant(true);
				}
				else
				{
					return Variant();
				}
			}
			case JSON_TYPE.FALSE:
			{
				static if (is(T : bool))
				{
					return Variant(false);
				}
				else
				{
					return Variant();
				}
			}
			default:
			{
				throw new InvalidJsonException("\"" ~ d.dataType ~ "\" property \"" ~ pi.name ~ "\" type mismatching");
			}
		}
	}
	else
		return Variant();
}
private Variant get(T)(JSONValue j, Data d, PropertyInfo pi) if (is(T : Data))
{
	if (pi.desc & TypeDesc.Data)
	{
		switch (j.type)
		{
			case JSON_TYPE.ARRAY:
			{
				T[] val;
				foreach (size_t i, e; j)
				{
					val ~= e.get!T(d, pi).get!T();
				}
				return Variant(val);
			}
			case JSON_TYPE.OBJECT:
			{
				static if (is(T : Data))
				{
					return Variant(j.createData());
				}
				else
				{
					return Variant();
				}
			}
			default:
			{
				throw new InvalidJsonException("\"" ~ d.dataType ~ "\" property \"" ~ pi.name ~ "\" type mismatching");
			}
		}
	}
	else
		return Variant();
}
