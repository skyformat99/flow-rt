module flowbase.data.meta;
import flowbase.data.interfaces;
import flowbase.data.types;
import flowbase.data.exceptions;

import std.traits;
import std.uuid;
import std.meta;

import flowbase.type.types;
import flowbase.type.interfaces;

mixin template TPropertySignalArgs()
{
	private string _propertyName;
	private TypeInfo _type;
	private Object _oldValue;
	private Object _newValue;

	@property string propertyName()
	{
		return this._propertyName;
	}

	@property TypeInfo type()
	{
		return this._type;
	}

	@property Object oldValue()
	{
		return this._oldValue;
	}

	@property Object newValue()
	{
		return this._newValue;
	}

	this(string propertyName, TypeInfo type, Object oldValue, Object newValue)
	{
		this._propertyName = propertyName;
		this._type = type;
		this._oldValue = oldValue;
		this._newValue = newValue;
	}
}

mixin template TTypedPropertySignalArgs(T)
{
	private T _oldValue;
	private T _newValue;

	@property T oldValue()
	{
		return this._oldValue;
	}

	@property T newValue()
	{
		return this._newValue;
	}

	this(T oldValue, T newValue)
	{
		this._oldValue = oldValue;
		this._newValue = newValue;
	}
}

/// base class for data objects
mixin template TDataObject()
{
	import flowbase.data.exceptions;

	static DataPropertyInfo[string] DataProperties;

	private UUID _id;
	private string _domain;
	private DataScope _availability = DataScope.Entity;

	@property UUID id()
	{
		return this._id;
	}

	@property string domain()
	{
		return this._domain;
	}

	@property DataScope availability()
	{
		return this._availability;
	}

	@property void availability(DataScope value)
	{
		this._availability = value;
	}

	static this()
	{
		staticInit();
	}

	this(DataBag initialBag, string domain)
	{
		this._id = randomUUID();
		this._domain = domain;

		initialBag.put(this);

        this.init();
	}

	this(DataBag initialBag, UUID id, string domain)
	{
		this._id = id;
		this._domain = domain;

		initialBag.put(this);

        this.init();
	}

	Object GetProperty(string name)
	{
		if(name !in DataProperties)
			throw new DataReflectionError("no data property named \"" ~ name ~ "\" found");

		return this.GetPropertyInternal(name);
	}

	void SetProperty(string name, Object value)
	{
		if(name !in DataProperties)
			throw new DataReflectionError("no data property named \"" ~ name ~ "\" found");
		
		if(typeid(value) != DataProperties[name].typeInfo)
			throw new DataReflectionError("data property \"" ~ name ~ "\" isn't of type \"" ~ typeid(value).toString ~ "\" but \"" ~ DataProperties[name].typeInfo.toString() ~ "\"");

		if(value is null && !DataProperties[name].isNullable)
			throw new DataReflectionError("data property \"" ~ name ~ "\" isn't nullable but given value is null");
		
		this.SetPropertyInternal(name, value);
	}

	private SPropertyChanging _propertyChanging = new SPropertyChanging();
	private SPropertyChanged _propertyChanged = new SPropertyChanged();

	@property SPropertyChanging propertyChanging()
	{
		return this._propertyChanging;
	}

	@property SPropertyChanged propertyChanged()
	{
		return this._propertyChanged;
	}
}

private struct DataPropertyMixins
{
	string name;
	string staticInitializer;
	string initializer;
	string property;
	string setProperty;
	string getProperty;
}

template DataProperty(T, string name) if (is(T : IDataObject)
		|| is(T : IDataList!A, A) || is(T : Ref!A, A) || isScalarType!T
		|| is(T == UUID) || is(T == string))
{
	enum hasSignals = true;

	static if (is(T : IDataList!A, A))
		enum hasSetter = false;
	else
		enum hasSetter = true;

	enum hasGetter = true;

	enum isNullable = !(isScalarType!T || is(T == UUID) || is(T == string));

	static if (!isNullable)
	{
		enum nullableValuePrefix = "new " ~ Ref!(T).stringof ~ "(";
		enum nullableValuePostfix = ")";
	}
	else
	{
		enum nullableValuePrefix = "";
		enum nullableValuePostfix = "";
	}

	static if (is(T : IDataList!B, B))
		enum initializer = "\n\t\t\t\tthis._" ~ name ~ " = new " ~ T.stringof ~ "();";
	else
		enum initializer = "";

	enum staticInitializer = "\n\t\t\t\tDataProperties[\"" ~ name ~ "\"] = DataPropertyInfo(typeid(" ~ T.stringof ~ "), " ~ (isNullable ? "true" : "false") ~ ");";

	enum type = T.stringof;

	enum signals = !hasSignals ? "" : "
			private STypedPropertyChanging!(" ~ type ~ ") _" ~ name	~ "Changing = new STypedPropertyChanging!(" ~ type ~ ")();
			private STypedPropertyChanged!(" ~ type ~ ") _" ~ name ~ "Changed = new STypedPropertyChanged!(" ~ type ~ ")();

			@property STypedPropertyChanging!(" ~ type ~ ") " ~ name ~ "Changing() {return this._" ~ name ~ "Changing;}
			@property STypedPropertyChanged!(" ~ type ~ ") " ~ name ~ "Changed() {return this._" ~ name ~ "Changed;}
		";

	enum setter = !hasSetter ? "" : "
			@property public void " ~ name ~ "(" ~ type ~ " value)
			{
				synchronized
					if(this._" ~ name ~ " != value)
					{
						" ~ type ~ " oldValue = this._" ~ name ~ ";
						auto changingArgs = new PropertyChangingSignalArgs(\"" ~ name ~ "\", typeid(this), " ~ nullableValuePrefix ~ "oldValue" ~ nullableValuePostfix ~ ", " ~ nullableValuePrefix ~ "value" ~ nullableValuePostfix ~ ");
						auto typedChangingArgs = new TypedPropertyChangingSignalArgs!(" ~ type ~ ")(oldValue, value);

						this." ~ name ~ "Changing.emit(this, typedChangingArgs);
						this.propertyChanging.emit(this, changingArgs);

						if(!typedChangingArgs.cancel && !changingArgs.cancel)
						{
							this._" ~ name ~ " =  value;

							auto typedChangedArgs = new TypedPropertyChangedSignalArgs!(" ~ type ~ ")(oldValue, value);
							auto changedArgs = new PropertyChangedSignalArgs(\"" ~ name ~ "\", typeid(this), " ~ nullableValuePrefix ~ "oldValue" ~ nullableValuePostfix ~ ", " ~ nullableValuePrefix ~ "value" ~ nullableValuePostfix ~ ");
							this." ~ name ~ "Changed.emit(this, typedChangedArgs);
							this.propertyChanged.emit(this, changedArgs);
						}
					}
			}
		";

	enum getter = !hasGetter ? "" : "
			@property public " ~ type ~ " " ~ name ~ "() { return this._" ~ name ~ "; }
		";

	enum property = "
			private " ~ type ~ " _" ~ name ~ ";

			" ~ signals ~ "
			" ~ setter ~ "
			" ~ getter ~ "
		";
	
	enum setProperty = hasSetter ? "this." ~ name ~ " = " ~ (!isNullable ? "(cast(Ref!" ~ T.stringof ~ ")value).value" : "cast(" ~ T.stringof ~ ")value") ~ ";" : "throw new DataReflectionError(\"property \\\"" ~ name ~ "\\\" has no setter\");";

	enum getProperty = "return " ~ nullableValuePrefix ~ "this." ~ name ~ nullableValuePostfix ~ ";";

	enum DataProperty = DataPropertyMixins(name, staticInitializer, initializer, property, setProperty, getProperty);
}

template DataObjectHelper(string name, properties...)
{
	string generateProperties()
	{
		string mixinString = "";
		foreach (property; aliasSeqOf!properties)
			mixinString ~= property.property;

		return mixinString;
	}

	string generateStaticInit()
	{
		string mixinString = "";
		foreach (property; aliasSeqOf!properties)
		{
			mixinString ~= property.staticInitializer;
		}

		return mixinString;
	}

	string generateInit()
	{
		string mixinString = "";
		foreach (property; aliasSeqOf!properties)
		{
			mixinString ~= property.initializer;
		}

		return mixinString;
	}

	string generateSetProperty()
	{
		string mixinString = "";
		foreach (property; aliasSeqOf!properties)
		{
			mixinString ~= "\n\t\t\t\tif(name == \"" ~ property.name ~ "\") {" ~ property.setProperty ~ "}";
		}

		return mixinString;
	}

	string generateGetProperty()
	{
		string mixinString = "";
		foreach (property; aliasSeqOf!properties)
		{
			mixinString ~= "\n\t\t\t\tif(name == \"" ~ property.name ~ "\") {" ~ property.getProperty ~ "}";
		}

		return mixinString;
	}
}

/// generates a data object
mixin template DataObject(string name, properties...)
{
	import std.uuid;
	import flowbase.data.signals;
	import flowbase.data.interfaces;
	import flowbase.data.meta;
	import flowbase.data.exceptions;
	import flowbase.data.types;

	mixin("
		class " ~ name ~ " : IDataObject
		{
			mixin TDataObject;

			static void staticInit()
			{" ~ DataObjectHelper!(name, properties).generateStaticInit() ~ "
			}

			void init()
			{" ~ DataObjectHelper!(name, properties).generateInit() ~ "
			}

			private void SetPropertyInternal(string name, Object value)
			{" ~ DataObjectHelper!(name, properties).generateSetProperty() ~ "
			}

			private Object GetPropertyInternal(string name)
			{" ~ DataObjectHelper!(name, properties).generateGetProperty() ~ "

				return null;
			}
				
" ~ DataObjectHelper!(name, properties).generateProperties() ~ "
		}");
}

/// outputs ctfe code
mixin template DataObjectPragmaMsg(string name, properties...)
{
	pragma(msg, "
		class " ~ name ~ " : IDataObject
		{
			mixin TDataObject;

			static void staticInit()
			{" ~ DataObjectHelper!(name, properties).generateStaticInit() ~ "
			}

			void init()
			{" ~ DataObjectHelper!(name, properties).generateInit() ~ "
			}

			void SetPropertyInternal(string name, Object value)
			{" ~ DataObjectHelper!(name, properties).generateSetProperty() ~ "
			}

			Object GetPropertyInternal(string name)
			{" ~ DataObjectHelper!(name, properties).generateGetProperty() ~ "
			}
				
" ~ DataObjectHelper!(name, properties).generateProperties() ~ "
		}");
}

/// generates a data object
mixin template DataObject(string name, string baseName, properties...) if (is(T : IDataObject))
{
	import std.uuid;
	import flowbase.data.signals;
	import flowbase.data.interfaces;
	import flowbase.data.meta;
	import flowbase.data.exceptions;
	import flowbase.data.types;

	mixin("
		class " ~ name ~ " : " ~ baseName ~ " 
		{
			mixin TDataObject;

			static void staticInit()
			{" ~ DataObjectHelper!(name, properties).generateStaticInit() ~ "
			}

			void init()
			{" ~ DataObjectHelper!(name, properties).generateInit() ~ "
			}

			private void SetPropertyInternal(string name, Object value)
			{" ~ DataObjectHelper!(name, properties).generateSetProperty() ~ "
			}

			private Object GetPropertyInternal(string name)
			{" ~ DataObjectHelper!(name, properties).generateGetProperty() ~ "

				return null;
			}
				
" ~ DataObjectHelper!(name, properties).generateProperties() ~ "
		}");
}

/// outputs ctfe code
mixin template DataObjectPragmaMsg(string name, string baseName, properties...) if (is(T : IDataObject))
{
	pragma(msg, "
		class " ~ name ~ " : " ~ baseName ~ "
		{
			mixin TDataObject;

			static void staticInit()
			{" ~ DataObjectHelper!(name, properties).generateStaticInit() ~ "
			}

			void init()
			{" ~ DataObjectHelper!(name, properties).generateInit() ~ "
			}

			void SetPropertyInternal(string name, Object value)
			{" ~ DataObjectHelper!(name, properties).generateSetProperty() ~ "
			}

			Object GetPropertyInternal(string name)
			{" ~ DataObjectHelper!(name, properties).generateGetProperty() ~ "
			}
				
" ~ DataObjectHelper!(name, properties).generateProperties() ~ "
		}");
}