// D import file generated from './msgpack/value.d'
module msgpack.value;
import msgpack.common;
import msgpack.attribute;
import msgpack.exception;
import std.json;
import std.container : Array;
import std.traits;
import std.typecons : Tuple, isTuple;
struct Value
{
	static enum Type 
	{
		nil,
		boolean,
		unsigned,
		signed,
		floating,
		array,
		map,
		raw,
		ext,
	}
	static union Via
	{
		bool boolean;
		ulong uinteger;
		long integer;
		real floating;
		Value[] array;
		Value[Value] map;
		ubyte[] raw;
		ExtValue ext;
	}
	Type type;
	Via via;
	@safe this(Type type)
	{
		this.type = type;
	}
	@safe this(typeof(null))
	{
		this(Type.nil);
	}
	@trusted this(bool value, Type type = Type.boolean)
	{
		this(type);
		via.boolean = value;
	}
	@trusted this(ulong value, Type type = Type.unsigned)
	{
		this(type);
		via.uinteger = value;
	}
	@trusted this(long value, Type type = Type.signed)
	{
		this(type);
		via.integer = value;
	}
	@trusted this(real value, Type type = Type.floating)
	{
		this(type);
		via.floating = value;
	}
	@trusted this(Value[] value, Type type = Type.array)
	{
		this(type);
		via.array = value;
	}
	@trusted this(Value[Value] value, Type type = Type.map)
	{
		this(type);
		via.map = value;
	}
	@trusted this(ubyte[] value, Type type = Type.raw)
	{
		this(type);
		via.raw = value;
	}
	@trusted this(string value, Type type = Type.raw)
	{
		this(type);
		via.raw = cast(ubyte[])value;
	}
	@trusted this(ExtValue value, Type type = Type.ext)
	{
		this(type);
		via.ext = value;
	}
	@property @trusted T as(T)() if (is(Unqual!T == bool))
	{
		if (type != Type.boolean)
			onCastError();
		return via.boolean;
	}
	@property @trusted T as(T)() if (isIntegral!T && !is(Unqual!T == enum))
	{
		if (type == Type.unsigned)
			return cast(T)via.uinteger;
		if (type == Type.signed)
			return cast(T)via.integer;
		onCastError();
		assert(false);
	}
	@property @trusted T as(T)() if (isFloatingPoint!T && !is(Unqual!T == enum))
	{
		if (type != Type.floating)
			onCastError();
		return cast(T)via.floating;
	}
	@property @trusted T as(T)() if (is(Unqual!T == enum))
	{
		return cast(T)as!(OriginalType!T);
	}
	@property @trusted T as(T)() if (is(Unqual!T == ExtValue))
	{
		if (type != Type.ext)
			onCastError();
		return cast(T)via.ext;
	}
	@property @trusted T as(T)() if ((isArray!T || isInstanceOf!(Array, T)) && !is(Unqual!T == enum))
	{
		alias V = typeof(T.init[0]);
		if (type == Type.nil)
		{
			static if (isDynamicArray!T)
			{
				return null;
			}
			else
			{
				return T.init;
			}
		}
		static if (isByte!V || isSomeChar!V)
		{
			if (type != Type.raw)
				onCastError();
			static if (isDynamicArray!T)
			{
				return cast(T)via.raw;
			}
			else
			{
				if (via.raw.length != T.length)
					onCastError();
				return cast(T)via.raw[0..T.length];
			}
		}
		else
		{
			if (type != Type.array)
				onCastError();
			V[] array;
			foreach (elem; via.array)
			{
				array ~= elem.as!V;
			}
			return array;
		}
	}
	@property @trusted T as(T)() if (isAssociativeArray!T)
	{
		alias K = typeof(T.init.keys[0]);
		alias V = typeof(T.init.values[0]);
		if (type == Type.nil)
			return null;
		if (type != Type.map)
			onCastError();
		V[K] map;
		foreach (key, value; via.map)
		{
			map[key.as!K] = value.as!V;
		}
		return map;
	}
	@property @trusted T as(T, Args...)(Args args) if (is(Unqual!T == class))
	{
		if (type == Type.nil)
			return null;
		T object = new T(args);
		static if (hasMember!(T, "fromMsgpack"))
		{
			static if (__traits(compiles, ()
			{
				object.fromMsgpack(this);
			}
			))
			{
				object.fromMsgpack(this);
			}
			else
			{
				static assert(0, "Failed to invoke 'fromMsgpack' on type '" ~ Unqual!T.stringof ~ "'");
			}
		}
		else
		{
			alias Classes = SerializingClasses!T;
			if (via.array.length != SerializingMemberNumbers!Classes)
				throw new MessagePackException("The number of deserialized object member is mismatched");
			size_t offset;
			foreach (Class; Classes)
			{
				Class obj = cast(Class)object;
				foreach (i, member; obj.tupleof)
				{
					static if (isPackedField!(Class.tupleof[i]))
					{
						obj.tupleof[i] = via.array[offset++].as!(typeof(member));
					}

				}
			}
		}
		return object;
	}
	@property @trusted T as(T)() if (is(Unqual!T == struct) && !is(Unqual!T == ExtValue))
	{
		T obj;
		static if (hasMember!(T, "fromMsgpack"))
		{
			static if (__traits(compiles, ()
			{
				obj.fromMsgpack(this);
			}
			))
			{
				obj.fromMsgpack(this);
			}
			else
			{
				static assert(0, "Failed to invoke 'fromMsgpack' on type '" ~ Unqual!T.stringof ~ "'");
			}
		}
		else
		{
			static if (isTuple!T)
			{
				if (via.array.length != T.Types.length)
					throw new MessagePackException("The number of deserialized Tuple element is mismatched");
				foreach (i, Type; T.Types)
				{
					obj.field[i] = via.array[i].as!Type;
				}
			}
			else
			{
				if (via.array.length != SerializingMemberNumbers!T)
					throw new MessagePackException("The number of deserialized struct member is mismatched");
				size_t offset;
				foreach (i, member; obj.tupleof)
				{
					static if (isPackedField!(T.tupleof[i]))
					{
						obj.tupleof[i] = via.array[offset++].as!(typeof(member));
					}

				}
			}
		}
		return obj;
	}
	const void toMsgpack(Packer)(ref Packer packer)
	{
		final switch (type)
		{
			case Type.nil:
			{
				packer.pack(null);
				break;
			}
			case Type.boolean:
			{
				packer.pack(via.boolean);
				break;
			}
			case Type.unsigned:
			{
				packer.pack(via.uinteger);
				break;
			}
			case Type.signed:
			{
				packer.pack(via.integer);
				break;
			}
			case Type.floating:
			{
				packer.pack(via.floating);
				break;
			}
			case Type.raw:
			{
				packer.pack(via.raw);
				break;
			}
			case Type.ext:
			{
				packer.packExt(via.ext.type, via.ext.data);
				break;
			}
			case Type.array:
			{
				packer.beginArray(via.array.length);
				foreach (elem; via.array)
				{
					elem.toMsgpack(packer);
				}
				break;
			}
			case Type.map:
			{
				packer.beginMap(via.map.length);
				foreach (key, value; via.map)
				{
					key.toMsgpack(packer);
					value.toMsgpack(packer);
				}
				break;
			}
		}
	}
	const @trusted bool opEquals(Tdummy = void)(ref const Value other)
	{
		if (type != other.type)
			return false;
		final switch (other.type)
		{
			case Type.nil:
			{
				return true;
			}
			case Type.boolean:
			{
				return opEquals(other.via.boolean);
			}
			case Type.unsigned:
			{
				return opEquals(other.via.uinteger);
			}
			case Type.signed:
			{
				return opEquals(other.via.integer);
			}
			case Type.floating:
			{
				return opEquals(other.via.floating);
			}
			case Type.raw:
			{
				return opEquals(other.via.raw);
			}
			case Type.ext:
			{
				return opEquals(other.via.ext);
			}
			case Type.array:
			{
				return opEquals(other.via.array);
			}
			case Type.map:
			{
				return opEquals(other.via.map);
			}
		}
	}
	const @trusted bool opEquals(T : bool)(in T other)
	{
		if (type != Type.boolean)
			return false;
		return via.boolean == other;
	}
	const @trusted bool opEquals(T : ulong)(in T other)
	{
		static if (__traits(isUnsigned, T))
		{
			if (type != Type.unsigned)
				return false;
			return via.uinteger == other;
		}
		else
		{
			if (type != Type.signed)
				return false;
			return via.integer == other;
		}
	}
	const @trusted bool opEquals(T : real)(in T other)
	{
		if (type != Type.floating)
			return false;
		return via.floating == other;
	}
	const @trusted bool opEquals(T : const(Value[]))(in T other)
	{
		if (type != Type.array)
			return false;
		return via.array == other;
	}
	const @trusted bool opEquals(T : const(Value[Value]))(in T other)
	{
		if (type != Type.map)
			return false;
		foreach (key, value; via.map)
		{
			if (key in other)
			{
				if (other[key] != value)
					return false;
			}
			else
			{
				return false;
			}
		}
		return true;
	}
	const @trusted bool opEquals(T : const(ubyte)[])(in T other)
	{
		if (type != Type.raw)
			return false;
		return via.raw == other;
	}
	const @trusted bool opEquals(T : string)(in T other)
	{
		if (type != Type.raw)
			return false;
		return via.raw == cast(ubyte[])other;
	}
	const @trusted bool opEquals(T : ExtValue)(in T other)
	{
		if (type != Type.ext)
			return false;
		return via.ext.type == other.type && via.ext.data == other.data;
	}
	const nothrow @trusted hash_t toHash();
}
@trusted JSONValue toJSONValue(in Value val);
@trusted Value fromJSONValue(in JSONValue val);
private pure @safe void onCastError();
