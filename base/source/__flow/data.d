module __flow.data;

import std.traits, std.uuid, std.meta, std.datetime, std.range.primitives;

import __flow.lib.vibe.data.json;
import __flow.type;

/// an error occured in data reflection layer (error stops execution of app)
class DataingError : Error
{
    this(string msg) {
        super(msg);
    }
}

/// an exception occured in data reflection layer (exception is catchable)
class DataingException : Exception
{
    this(string msg) {
        super(msg);
    }
}

/// data property meta informations
struct PropertyMeta
{
	string type;
	string name;
	bool isList;
	bool isData;
	bool isNullable;
	bool isArray;
	bool isScalar;
	string refPrefix = "";
	string refPostfix = "";
}

/// data property informations
struct PropertyInfo
{
	TypeInfo typeInfo;
	bool isList;
	bool isData;
}

/// get the value of a data field by its name
T get(T)(Data obj, string name) if(is(T : Data))
{
	if(name !in obj.dataProperties)
		throw new DataingException("no data property named \""~name~"\" found");

	return obj.getGeneric(name).as!T;
}

/// get the value of a data field by its name
T get(T)(Data obj, string name) if(isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	if(name !in obj.dataProperties)
		throw new DataingException("no data property named \""~name~"\" found");

	return obj.getGeneric(name).as(Ref!T).value;
}

/// set the value of a data property by its name
Data set(T)(Data obj, string name, T value) if(is(T : Data))
{
	if(name !in obj.dataProperties)
		throw new DataingException("no data property named \""~name~"\" found");

	if(value is null && !obj.dataProperties[name].isData)
		throw new DataingException("data property \""~name~"\" isn't nullable but given value is null");

	if(value !is null && typeid(value) != cast(TypeInfo)obj.dataProperties[name].typeInfo)
		throw new DataingException("data property \""~name~"\" isn't of type \""~typeid(value).toString~"\" but \""~(cast(TypeInfo)obj.dataProperties[name].typeInfo).toString()~"\"");
			
	obj.setGeneric(name, value);

	return obj;
}

/// set the value of a data property by its name
Data set(T)(Data obj, string name, T value) if(isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	if(name !in obj.dataProperties)
		throw new DataingException("no data property named \""~name~"\" found");

	if(typeid(value) != cast(TypeInfo)obj.dataProperties[name].typeInfo)
		throw new DataingException("data property \""~name~"\" isn't of type \""~typeid(value).toString~"\" but \""~(cast(TypeInfo)obj.dataProperties[name].typeInfo).toString()~"\"");
			
	obj.setGeneric(name, new Ref!T(value));

	return obj;
}

abstract class Data : __IFqn
{
	import __flow.event;
	
	private shared static Data function()[string] _reg;

	static void register(string dataType, Data function() creator)
	{
		_reg[dataType] = creator;
	}

	static bool knows(string dataType)
	{
		return dataType in _reg ? true : false;
	}

	static Data create(string dataType)
	{
		if(dataType in _reg)
			return _reg[dataType]();
		else
			return null;
	}

	static Data fromJson(string s)
	{
		auto j = parseJsonString(s);
		return fromJson(j);
	}

	static Data fromJson(Json j)
	{
		auto type = j["dataType"].deserializeJson!string;
		auto obj = create(type);
		if(obj !is null) obj.fillFromJson(j);
		return obj;
	}

	@property shared(PropertyInfo[string]) dataProperties(){return null;}	
	private EPropertyChanging _propertyChanging;
	private EPropertyChanged _propertyChanged;
	
	@property EPropertyChanging propertyChanging()
	{
		return this._propertyChanging;
	}

	@property EPropertyChanged propertyChanged()
	{
		return this._propertyChanged;
	}
	
	abstract @property string __fqn();
	@property string dataType(){return this.__fqn;}

	this()
	{
		// create events
		this._propertyChanging = new EPropertyChanging();
		this._propertyChanged = new EPropertyChanged();
	}

	Data clone()
	{
		return this.dup;
	}

	string toJson(){return this.toJsonStruct().toString();}

	abstract Data dup();
	abstract protected void dupInternal(Data c);
	abstract Object getGeneric(string name);
	abstract bool setGeneric(string name, Object value);
	abstract Json toJsonStruct();
	abstract protected void toJson(Json j);
	abstract void fillFromJson(Json j);
}

/// implements code of a data object
mixin template TData()
{
	import std.traits, std.array, std.conv;
	import __flow.lib.vibe.data.serialization, __flow.lib.vibe.data.json;
	import __flow.event, __flow.type, __flow.data;

	shared static PropertyInfo[string] DataProperties;
	override @property shared(PropertyInfo[string]) dataProperties(){return DataProperties;}
	private shared static void function(typeof(this))[] _inits;
	private shared static Object function(typeof(this), string)[] _getter;
	private shared static bool function(typeof(this), string, Object)[] _setter;
	private shared static void function(typeof(this), typeof(this))[] _dups;
	private shared static void function(typeof(this), Json)[] _toJsons;
	private shared static void function(typeof(this), Json)[] _fromJsons;

	static Data create() {return new typeof(this);}

	shared static this()
	{
		static if(fqn!(typeof(super)) != "__flow.data.Data")
		foreach(n, i; super.DataProperties)
			DataProperties[n] = i;

		Data.register(fqn!(typeof(this)), &create);
	}

	override @property string __fqn() {return fqn!(typeof(this));}

	this()
	{
		// execute initializers
		foreach(i; _inits) i(this);

		super();
	}
	
	override Object getGeneric(string name)
	{
		Object value = null;
		static if(fqn!(typeof(super)) != "__flow.data.Data")
			value = super.getGeneric(name);

		if(value is null)
		{
			foreach(g; _getter)
			{
				value = g(this, name);
				if(value !is null) break;
			}
		} 

		return value;
	}

	override bool setGeneric(string name, Object value)
	{
		auto set = false;
		static if(fqn!(typeof(super)) != "__flow.data.Data")
			super.setGeneric(name, value);

		if(!set)
			foreach(s; _setter)
			{
				set = s(this, name, value);
				if(set) break;
			}
		return set;
	}

	override typeof(this) dup()
	{
		auto c = new typeof(this);
		this.dupInternal(c);
		return c;
	}

	override protected void dupInternal(Data c)
	{
		static if(fqn!(typeof(super)) != "__flow.data.Data")
			super.dupInternal(c);

		auto clone = cast(typeof(this))c;
		foreach(d; _dups)
			d(this, clone);
	}
		
	override Json toJsonStruct()
	{
		auto j = Json(["dataType" : Json(this.dataType)]);
		this.toJson(j);
		return j;
	}

	alias toJson = Data.toJson;
	override protected void toJson(Json j)
	{
		static if(fqn!(typeof(super)) != "__flow.data.Data")
			super.toJson(j);
		
		auto len = _toJsons.length;
		foreach(tj; _toJsons)
			tj(this, j);
	}

	static typeof(this) fromJson(string s)
	{
		return fromJson(parseJsonString(s));
	}

	static typeof(this) fromJson(Json j)
	{
		auto obj = new typeof(this);
		obj.fillFromJson(j);
		return obj;	
	}

	override void fillFromJson(Json j)
	{
		static if(fqn!(typeof(super)) != "__flow.data.Data")
			super.fillFromJson(j);
			
		foreach(fj; _fromJsons)
			fj(this, j);
	}
}

template TFieldHelper(PropertyMeta p)
{
	string events()
	{
		return "
			private ETypedPropertyChanging!("~p.type~") _"~p.name~ "Changing;
			private ETypedPropertyChanged!("~p.type~") _"~p.name~"Changed;
			@property ETypedPropertyChanging!("~p.type~") "~p.name~"Changing()
			{return this._"~p.name~"Changing;}
			@property ETypedPropertyChanged!("~p.type~") "~p.name~"Changed()
			{return this._"~p.name~"Changed;}
		";
	}
	
	string getter()
	{
		return "
			@property "~p.type~" "~p.name~"() { synchronized(this._"~p.name~"Lock.reader) return this._"~p.name~"; }
		";
	}

	string setter()
	{
		return "
			@property void "~p.name~"("~p.type~" value)
			{
				synchronized(this._"~p.name~"Lock.writer)
					this."~p.name~"Internal(value);
			}
			
			bool "~p.name~"Try("~p.type~" value)
			{
				auto locked = this._"~p.name~"Lock.writer.tryLock();
				try{if(locked) this."~p.name~"Internal(value);}
				finally {this._"~p.name~"Lock.writer.unlock();}
				return locked;
			}
			
			void "~p.name~"Internal("~p.type~" value)
			{
				if(this._"~p.name~" != value)
				{
					"~p.type~" oldValue = this._"~p.name~";
					auto changingArgs = new PropertyChangingEventArgs(\""~p.name~"\", typeid(this), "~p.refPrefix~"oldValue"~p.refPostfix~", "~p.refPrefix~"value"~p.refPostfix~");
					auto typedChangingArgs = new TypedPropertyChangingEventArgs!("~p.type~")(oldValue, value);
					this."~p.name~"Changing.emit(this, typedChangingArgs);
					this.propertyChanging.emit(this, changingArgs);
					if(!typedChangingArgs.cancel && !changingArgs.cancel)
					{
						this._"~p.name~" =  value;
						auto typedChangedArgs = new TypedPropertyChangedEventArgs!("~p.type~")(oldValue, value);
						auto changedArgs = new PropertyChangedEventArgs(\""~p.name~"\", typeid(this), "~p.refPrefix~"oldValue"~p.refPostfix~", "~p.refPrefix~"value"~p.refPostfix~");
						this."~p.name~"Changed.emit(this, typedChangedArgs);
						this.propertyChanged.emit(this, changedArgs);
					}
				}
			}
		";
	}
	
	string init()
	{
		string initString = "
			_inits ~= (t){
				t._"~p.name~"Lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
				t._"~p.name~"Changing = new ETypedPropertyChanging!("~p.type~")();
				t._"~p.name~"Changed = new ETypedPropertyChanged!("~p.type~")();
			};
		";

		string getterString = "
			_getter ~= (t, name){
				if(name == \""~p.name~"\")
					return "~p.refPrefix~"t."~p.name~p.refPostfix~";
				else
					return null;
			};
		";

		string setterString = "
			_setter ~= (t, name, value){
				if(name == \""~p.name~"\")
				{
					t."~p.name~" = "~(!p.isData ? "(cast(Ref!("~p.type~"))value).value" : "cast("~p.type~")value")~";
					return true;
				}
				else return false;
			};
		";

		string dupString = "
			_dups ~= (t, c){
				static if("~p.isData.stringof~")
				{if(t."~p.name~" !is null) c._"~p.name~" = t."~p.name~".dup;}
				else{c._"~p.name~" = t."~p.name~";}
			};
		";

		string toJsonString = "_toJsons ~= (t, j){";
		if(p.isData)
			toJsonString ~= "if(t."~p.name~" !is null) j[\""~p.name~"\"] = t."~p.name~".toJsonStruct();};";
		else if(p.isArray)
			toJsonString ~= "if(t."~p.name~" !is null) j[\""~p.name~"\"] = t."~p.name~".serializeToJson();};";
		else if(p.type == "UUID")
			toJsonString ~= "j[\""~p.name~"\"] = t."~p.name~".toString();};";
		else if(p.type == "SysTime" || p.type == "DateTime")
			toJsonString ~= "j[\""~p.name~"\"] = t."~p.name~".toISOExtString();};";
		else
			toJsonString ~= "j[\""~p.name~"\"] = t."~p.name~";};";
		
		string fromJsonString = "_fromJsons ~= (t, j){if(\""~p.name~"\" in j)";
		if(p.isData) 
			fromJsonString ~= "t._"~p.name~" = cast("~p.type~")Data.fromJson(j[\""~p.name~"\"]);};";
		else if(p.isArray)
			fromJsonString ~= "t._"~p.name~" = j[\""~p.name~"\"].deserializeJson!("~p.type~");};";
		else if(p.type == "UUID")
			fromJsonString ~= "t._"~p.name~" = parseUUID(j[\""~p.name~"\"].get!string);};";
		else if(p.type == "SysTime" || p.type == "DateTime")
			fromJsonString ~= "t._"~p.name~" = "~p.type~".fromISOExtString(j[\""~p.name~"\"].get!string);};";
		else
			fromJsonString ~= "t._"~p.name~" = j[\""~p.name~"\"].get!("~p.type~");};";

		return "
			shared static this()
			{
				DataProperties[\""~p.name~"\"] = cast(shared(PropertyInfo))PropertyInfo(typeid("~p.type~"), false, "~(p.isData ? "true" : "false")~");
				
				"~initString~"
				"~getterString~"
				"~setterString~"
				"~dupString~"
				"~toJsonString~"
				"~fromJsonString~"
			}
		";
	}
}

template TListHelper(PropertyMeta p)
{
	string init()
	{
		return "
			shared static this()
			{
				DataProperties[\""~p.name~"\"] = cast(shared(PropertyInfo))PropertyInfo(typeid("~p.type~"), true, false);

				_inits ~= (t){
					t._"~p.name~" = new DataList!("~p.type~");
				};

				_getter ~= (t, name){
					if(name == \""~p.name~"\")
						return cast(DataList!("~p.type~"))t."~p.name~";
					else
						return null;
				};

				_setter ~= (t, name, value){
					if(name == \""~p.name~"\")
						throw new DataingException(\"property \\\""~p.name~"\\\" has no setter\");
					else return false;
				};

				_dups ~= (t, c){
					c._"~p.name~" = (cast(DataList!("~p.type~"))t."~p.name~").dup;
				};

				_toJsons ~= (t, j){
					Json[] "~p.name~";
					foreach(e; t."~p.name~")
					{
						"~(p.type == "UUID" ? 
							p.name~" ~= e.toString().serializeToJson();" :
							"")~"
						"~(p.type == "SysTime" || p.type == "DateTime" ?
							p.name~" ~= Json(e.toISOExtString());" :
							"")~"
						"~(p.isScalar && p.type != "UUID" && p.type != "SysTime" && p.type != "DateTime" ?
							p.name~" ~= Json(e);" :
							"")~"
						"~(p.isData ?
							p.name~" ~= e.toJsonStruct();" :
							"")~"
						"~(p.isArray ?
							p.name~" ~= e.serializeToJson();" :
							"")~"
					}
					if(!"~p.name~".empty)
						j[\""~p.name~"\"] = Json("~p.name~");
				};

				_fromJsons ~= (t, j){
					if(\""~p.name~"\" in j)
					{
						"~p.type~"[] "~p.name~"; 
						foreach(e; j[\""~p.name~"\"])
						{
							"~(p.type == "UUID" ? 
								p.name~" ~= parseUUID(e.deserializeJson!(string));" :
								"")~"
							"~(p.type == "SysTime" || p.type == "DateTime" ?
								p.name~" ~= "~p.type~".fromISOExtString(e.get!string);" :
								"")~"
							"~(p.isScalar && p.type != "UUID" && p.type != "SysTime" && p.type != "DateTime" ?
								(p.name~" ~= e.get!("~p.type~");") :
								"")~"
							"~(p.isData ?
								("auto obj = cast("~p.type~")Data.fromJson(e); if(obj !is null) "~p.name~" ~= obj;") :
								"")~"
							"~(p.isArray ?
								("auto arr = e.deserializeJson!("~p.type~"); if(arr !is null) "~p.name~" ~= arr;") :
								"")~"
						}
						if(!"~p.name~".empty)
							t."~p.name~".put("~p.name~");
					}
				};
			}
		";
	}
}

/// creates a field property
mixin template TField(T, string name)
	if ((is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{
	import core.sync.rwmutex;
	import std.traits, std.array, std.conv;
	import __flow.lib.vibe.data.json, __flow.lib.vibe.data.serialization;
	import __flow.event, __flow.type, __flow.data;	

	enum isData = is(T : Data);
	enum p = PropertyMeta(
		T.stringof,
		name,
		false,
		isData,
		isArray!T || isData,
		isArray!T,
		!isData && !isArray!T,
		isData ? "" : "new Ref!("~T.stringof~")(",
		isData ? "" : ")"
	);

	alias h = TFieldHelper!p;
	enum mixinString = "
		private ReadWriteMutex _"~p.name~"Lock;
		private "~p.type~" _"~p.name~";
		"~h.events~"
		"~h.getter~"
		"~h.setter~"
		"~h.init~"
	";

	//pragma(msg, mixinString);
	mixin(mixinString);
}

/// creates a list property
mixin template TList(T, string name)
	if ((is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))))
{
	import core.sync.rwmutex;
	import std.traits, std.array, std.conv;
	import __flow.lib.vibe.data.json, __flow.lib.vibe.data.serialization;
	import __flow.event, __flow.type, __flow.data;

	enum isData = is(T : Data);
	enum p = PropertyMeta(
		T.stringof,
		name,
		true,
		isData,
		isArray!T || is(T : Data),
		isArray!T,
		!isData && !isArray!T);
	
	alias h = TListHelper!p;
	enum mixinString = "
		private DataList!("~p.type~") _"~p.name~";
		@property DataList!("~p.type~") "~p.name~"() { return this._"~p.name~"; }
		"~h.init~"
	";

	//pragma(msg, mixinString);
	mixin(mixinString);
}