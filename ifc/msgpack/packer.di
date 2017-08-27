// D import file generated from './msgpack/packer.d'
module msgpack.packer;
import msgpack.common;
import msgpack.attribute;
import msgpack.exception;
import std.array;
import std.exception;
import std.range;
import std.stdio;
import std.traits;
import std.typecons;
import std.typetuple;
import std.container;
struct PackerImpl(Stream) if (isOutputRange!(Stream, ubyte) && isOutputRange!(Stream, ubyte[]))
{
	private 
	{
		static @system 
		{
			alias PackHandler = void delegate(ref PackerImpl, void*);
			PackHandler[TypeInfo] packHandlers;
			public void registerHandler(T, alias Handler)()
			{
				packHandlers[typeid(T)] = delegate (ref PackerImpl packer, void* obj)
				{
					Handler(packer, *cast(T*)obj);
				}
				;
			}
			public void register(T)()
			{
				packHandlers[typeid(T)] = delegate (ref PackerImpl packer, void* obj)
				{
					packer.packObject(*cast(T*)obj);
				}
				;
			}
		}
		enum size_t Offset = 1;
		Stream stream_;
		ubyte[Offset + RealSize] store_;
		bool withFieldName_;
		public 
		{
			this(Stream stream, bool withFieldName = false)
			{
				stream_ = stream;
				withFieldName_ = withFieldName;
			}
			this(bool withFieldName)
			{
				withFieldName_ = withFieldName;
			}
			nothrow @property ref @safe Stream stream()
			{
				return stream_;
			}
			ref PackerImpl pack(T)(in T value) if (is(Unqual!T == bool))
			{
				if (value)
					stream_.put(Format.TRUE);
				else
					stream_.put(Format.FALSE);
				return this;
			}
			ref PackerImpl pack(T)(in T value) if (isUnsigned!T && !is(Unqual!T == enum))
			{
				static if (!is(Unqual!T == ulong))
				{
					enum Bits = T.sizeof * 8;
					if (value < 1 << 8)
					{
						if (value < 1 << 7)
						{
							stream_.put(take8from!Bits(value));
						}
						else
						{
							store_[0] = Format.UINT8;
							store_[1] = take8from!Bits(value);
							stream_.put(store_[0..Offset + (ubyte).sizeof]);
						}
					}
					else
					{
						if (value < 1 << 16)
						{
							const temp = convertEndianTo!16(value);
							store_[0] = Format.UINT16;
							*cast(ushort*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (ushort).sizeof]);
						}
						else
						{
							const temp = convertEndianTo!32(value);
							store_[0] = Format.UINT32;
							*cast(uint*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (uint).sizeof]);
						}
					}
				}
				else
				{
					if (value < 1LU << 8)
					{
						if (value < 1LU << 7)
						{
							stream_.put(take8from!64(value));
						}
						else
						{
							store_[0] = Format.UINT8;
							store_[1] = take8from!64(value);
							stream_.put(store_[0..Offset + (ubyte).sizeof]);
						}
					}
					else
					{
						if (value < 1LU << 16)
						{
							const temp = convertEndianTo!16(value);
							store_[0] = Format.UINT16;
							*cast(ushort*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (ushort).sizeof]);
						}
						else if (value < 1LU << 32)
						{
							const temp = convertEndianTo!32(value);
							store_[0] = Format.UINT32;
							*cast(uint*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (uint).sizeof]);
						}
						else
						{
							const temp = convertEndianTo!64(value);
							store_[0] = Format.UINT64;
							*cast(ulong*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (ulong).sizeof]);
						}
					}
				}
				return this;
			}
			ref PackerImpl pack(T)(in T value) if (isSigned!T && isIntegral!T && !is(Unqual!T == enum))
			{
				static if (!is(Unqual!T == long))
				{
					enum Bits = T.sizeof * 8;
					if (value < -(1 << 5))
					{
						if (value < -(1 << 15))
						{
							const temp = convertEndianTo!32(value);
							store_[0] = Format.INT32;
							*cast(int*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (int).sizeof]);
						}
						else if (value < -(1 << 7))
						{
							const temp = convertEndianTo!16(value);
							store_[0] = Format.INT16;
							*cast(short*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (short).sizeof]);
						}
						else
						{
							store_[0] = Format.INT8;
							store_[1] = take8from!Bits(value);
							stream_.put(store_[0..Offset + (byte).sizeof]);
						}
					}
					else if (value < 1 << 7)
					{
						stream_.put(take8from!Bits(value));
					}
					else
					{
						if (value < 1 << 8)
						{
							store_[0] = Format.UINT8;
							store_[1] = take8from!Bits(value);
							stream_.put(store_[0..Offset + (ubyte).sizeof]);
						}
						else if (value < 1 << 16)
						{
							const temp = convertEndianTo!16(value);
							store_[0] = Format.UINT16;
							*cast(ushort*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (ushort).sizeof]);
						}
						else
						{
							const temp = convertEndianTo!32(value);
							store_[0] = Format.UINT32;
							*cast(uint*)&store_[Offset] = temp;
							stream_.put(store_[0..Offset + (uint).sizeof]);
						}
					}
				}
				else
				{
					if (value < -(1L << 5))
					{
						if (value < -(1L << 15))
						{
							if (value < -(1L << 31))
							{
								const temp = convertEndianTo!64(value);
								store_[0] = Format.INT64;
								*cast(long*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (long).sizeof]);
							}
							else
							{
								const temp = convertEndianTo!32(value);
								store_[0] = Format.INT32;
								*cast(int*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (int).sizeof]);
							}
						}
						else
						{
							if (value < -(1L << 7))
							{
								const temp = convertEndianTo!16(value);
								store_[0] = Format.INT16;
								*cast(short*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (short).sizeof]);
							}
							else
							{
								store_[0] = Format.INT8;
								store_[1] = take8from!64(value);
								stream_.put(store_[0..Offset + (byte).sizeof]);
							}
						}
					}
					else if (value < 1L << 7)
					{
						stream_.put(take8from!64(value));
					}
					else
					{
						if (value < 1L << 16)
						{
							if (value < 1L << 8)
							{
								store_[0] = Format.UINT8;
								store_[1] = take8from!64(value);
								stream_.put(store_[0..Offset + (ubyte).sizeof]);
							}
							else
							{
								const temp = convertEndianTo!16(value);
								store_[0] = Format.UINT16;
								*cast(ushort*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (ushort).sizeof]);
							}
						}
						else
						{
							if (value < 1L << 32)
							{
								const temp = convertEndianTo!32(value);
								store_[0] = Format.UINT32;
								*cast(uint*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (uint).sizeof]);
							}
							else
							{
								const temp = convertEndianTo!64(value);
								store_[0] = Format.UINT64;
								*cast(ulong*)&store_[Offset] = temp;
								stream_.put(store_[0..Offset + (ulong).sizeof]);
							}
						}
					}
				}
				return this;
			}
			ref PackerImpl pack(T)(in T value) if (isSomeChar!T && !is(Unqual!T == enum))
			{
				static if (is(Unqual!T == char))
				{
					return pack(cast(ubyte)value);
				}
				else
				{
					static if (is(Unqual!T == wchar))
					{
						return pack(cast(ushort)value);
					}
					else
					{
						static if (is(Unqual!T == dchar))
						{
							return pack(cast(uint)value);
						}

					}
				}
			}
			ref PackerImpl pack(T)(in T value) if (isFloatingPoint!T && !is(Unqual!T == enum))
			{
				static if (is(Unqual!T == float))
				{
					const temp = convertEndianTo!32(_f(value).i);
					store_[0] = Format.FLOAT;
					*cast(uint*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (uint).sizeof]);
				}
				else
				{
					static if (is(Unqual!T == double))
					{
						const temp = convertEndianTo!64(_d(value).i);
						store_[0] = Format.DOUBLE;
						*cast(ulong*)&store_[Offset] = temp;
						stream_.put(store_[0..Offset + (ulong).sizeof]);
					}
					else
					{
						static if ((real).sizeof > (double).sizeof && EnableReal)
						{
							store_[0] = Format.REAL;
							const temp = _r(value);
							const fraction = convertEndianTo!64(temp.fraction);
							const exponent = convertEndianTo!16(temp.exponent);
							*cast(Unqual!(typeof(fraction))*)&store_[Offset] = fraction;
							*cast(Unqual!(typeof(exponent))*)&store_[Offset + fraction.sizeof] = exponent;
							stream_.put(store_[0..$]);
						}
						else
						{
							pack(cast(double)value);
						}
					}
				}
				return this;
			}
			ref PackerImpl pack(T)(in T value) if (is(Unqual!T == enum))
			{
				pack(cast(OriginalType!T)value);
				return this;
			}
			static if (!is(typeof(null) == void*))
			{
				ref PackerImpl pack(T)(in T value) if (is(Unqual!T == typeof(null)))
				{
					return packNil();
				}
			}
			ref PackerImpl pack(T)(in T value) if (isPointer!T)
			{
				static if (is(Unqual!T == void*))
				{
					enforce(value is null, "Can't serialize void type");
					stream_.put(Format.NIL);
				}
				else
				{
					if (value is null)
						stream_.put(Format.NIL);
					else
						pack(mixin(AsteriskOf!T ~ "value"));
				}
				return this;
			}
			ref PackerImpl pack(T)(in T array) if ((isArray!T || isInstanceOf!(Array, T)) && !is(Unqual!T == enum))
			{
				alias U = typeof(T.init[0]);
				if (array.empty)
					return packNil();
				static if (isByte!U || isSomeChar!U)
				{
					ubyte[] raw = cast(ubyte[])array;
					beginRaw(raw.length);
					stream_.put(raw);
				}
				else
				{
					beginArray(array.length);
					foreach (elem; array)
					{
						pack(elem);
					}
				}
				return this;
			}
			ref PackerImpl pack(T)(in T array) if (isAssociativeArray!T)
			{
				if (array is null)
					return packNil();
				beginMap(array.length);
				foreach (key, value; array)
				{
					pack(key);
					pack(value);
				}
				return this;
			}
			ref PackerImpl pack(Types...)(auto ref const Types objects) if (Types.length > 1)
			{
				foreach (i, T; Types)
				{
					pack(objects[i]);
				}
				return this;
			}
			ref PackerImpl pack(T)(in T object) if (is(Unqual!T == class))
			{
				if (object is null)
					return packNil();
				static if (hasMember!(T, "toMsgpack"))
				{
					static if (__traits(compiles, ()
					{
						object.toMsgpack(this, withFieldName_);
					}
					))
					{
						object.toMsgpack(this, withFieldName_);
					}
					else
					{
						static if (__traits(compiles, ()
						{
							object.toMsgpack(this);
						}
						))
						{
							object.toMsgpack(this);
						}
						else
						{
							static assert(0, "Failed to invoke 'toMsgpack' on type '" ~ Unqual!T.stringof ~ "'");
						}
					}
				}
				else
				{
					if (auto handler = object.classinfo in packHandlers)
					{
						(*handler)(this, cast(void*)&object);
						return this;
					}
					if (T.classinfo !is object.classinfo)
					{
						throw new MessagePackException("Can't pack derived class through reference to base class.");
					}
					packObject!T(object);
				}
				return this;
			}
			ref @trusted PackerImpl pack(T)(auto ref T object) if (is(Unqual!T == struct) && !isInstanceOf!(Array, T) && !is(Unqual!T == ExtValue))
			{
				static if (hasMember!(T, "toMsgpack"))
				{
					static if (__traits(compiles, ()
					{
						object.toMsgpack(this, withFieldName_);
					}
					))
					{
						object.toMsgpack(this, withFieldName_);
					}
					else
					{
						static if (__traits(compiles, ()
						{
							object.toMsgpack(this);
						}
						))
						{
							object.toMsgpack(this);
						}
						else
						{
							static assert(0, "Failed to invoke 'toMsgpack' on type '" ~ Unqual!T.stringof ~ "'");
						}
					}
				}
				else
				{
					static if (isTuple!T)
					{
						beginArray(object.field.length);
						foreach (f; object.field)
						{
							pack(f);
						}
					}
					else
					{
						if (auto handler = typeid(Unqual!T) in packHandlers)
						{
							(*handler)(this, cast(void*)&object);
							return this;
						}
						immutable memberNum = SerializingMemberNumbers!T;
						if (withFieldName_)
							beginMap(memberNum);
						else
							beginArray(memberNum);
						if (withFieldName_)
						{
							foreach (i, f; object.tupleof)
							{
								static if (isPackedField!(T.tupleof[i]) && __traits(compiles, ()
								{
									pack(f);
								}
								))
								{
									pack(getFieldName!(T, i));
									pack(f);
								}

							}
						}
						else
						{
							foreach (i, f; object.tupleof)
							{
								static if (isPackedField!(T.tupleof[i]) && __traits(compiles, ()
								{
									pack(f);
								}
								))
								{
									pack(f);
								}

							}
						}
					}
				}
				return this;
			}
			void packObject(T)(in T object) if (is(Unqual!T == class))
			{
				alias Classes = SerializingClasses!T;
				immutable memberNum = SerializingMemberNumbers!Classes;
				if (withFieldName_)
					beginMap(memberNum);
				else
					beginArray(memberNum);
				foreach (Class; Classes)
				{
					Class obj = cast(Class)object;
					if (withFieldName_)
					{
						foreach (i, f; obj.tupleof)
						{
							static if (isPackedField!(Class.tupleof[i]))
							{
								pack(getFieldName!(Class, i));
								pack(f);
							}

						}
					}
					else
					{
						foreach (i, f; obj.tupleof)
						{
							static if (isPackedField!(Class.tupleof[i]))
							{
								pack(f);
							}

						}
					}
				}
			}
			ref PackerImpl packArray(Types...)(auto ref const Types objects)
			{
				beginArray(Types.length);
				foreach (i, T; Types)
				{
					pack(objects[i]);
				}
				return this;
			}
			ref PackerImpl packMap(Types...)(auto ref const Types objects)
			{
				static assert(Types.length % 2 == 0, "The number of arguments must be even");
				beginMap(Types.length / 2);
				foreach (i, T; Types)
				{
					pack(objects[i]);
				}
				return this;
			}
			ref PackerImpl pack(T)(auto ref const T data) if (is(Unqual!T == ExtValue))
			{
				packExt(data.type, data.data);
				return this;
			}
			ref PackerImpl packExt(in byte type, const ubyte[] data)
			{
				ref PackerImpl packExtFixed(int fmt);
				if (data.length == 1)
					return packExtFixed(Format.EXT + 0);
				else if (data.length == 2)
					return packExtFixed(Format.EXT + 1);
				else if (data.length == 4)
					return packExtFixed(Format.EXT + 2);
				else if (data.length == 8)
					return packExtFixed(Format.EXT + 3);
				else if (data.length == 16)
					return packExtFixed(Format.EXT + 4);
				int typeByte = void;
				if (data.length <= 2 ^^ 8 - 1)
				{
					store_[0] = Format.EXT8;
					store_[1] = cast(ubyte)data.length;
					typeByte = 2;
				}
				else if (data.length <= 2 ^^ 16 - 1)
				{
					store_[0] = Format.EXT16;
					const temp = convertEndianTo!16(data.length);
					*cast(ushort*)&store_[Offset] = temp;
					typeByte = 3;
				}
				else if (data.length <= 2 ^^ 32 - 1)
				{
					store_[0] = Format.EXT32;
					const temp = convertEndianTo!32(data.length);
					*cast(uint*)&store_[Offset] = temp;
					typeByte = 5;
				}
				else
					throw new MessagePackException("Data too large to pack as EXT");
				store_[typeByte] = type;
				stream_.put(store_[0..typeByte + 1]);
				stream_.put(data);
				return this;
			}
			void beginRaw(in size_t length)
			{
				import std.conv : text;
				if (length < 32)
				{
					const ubyte temp = Format.RAW | cast(ubyte)length;
					stream_.put(take8from(temp));
				}
				else if (length < 65536)
				{
					const temp = convertEndianTo!16(length);
					store_[0] = Format.RAW16;
					*cast(ushort*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (ushort).sizeof]);
				}
				else
				{
					if (length > 4294967295u)
						throw new MessagePackException(text("size of raw is too long to pack: ", length, " bytes should be <= ", 4294967295u));
					const temp = convertEndianTo!32(length);
					store_[0] = Format.RAW32;
					*cast(uint*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (uint).sizeof]);
				}
			}
			ref PackerImpl beginArray(in size_t length)
			{
				if (length < 16)
				{
					const ubyte temp = Format.ARRAY | cast(ubyte)length;
					stream_.put(take8from(temp));
				}
				else if (length < 65536)
				{
					const temp = convertEndianTo!16(length);
					store_[0] = Format.ARRAY16;
					*cast(ushort*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (ushort).sizeof]);
				}
				else
				{
					const temp = convertEndianTo!32(length);
					store_[0] = Format.ARRAY32;
					*cast(uint*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (uint).sizeof]);
				}
				return this;
			}
			ref PackerImpl beginMap(in size_t length)
			{
				if (length < 16)
				{
					const ubyte temp = Format.MAP | cast(ubyte)length;
					stream_.put(take8from(temp));
				}
				else if (length < 65536)
				{
					const temp = convertEndianTo!16(length);
					store_[0] = Format.MAP16;
					*cast(ushort*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (ushort).sizeof]);
				}
				else
				{
					const temp = convertEndianTo!32(length);
					store_[0] = Format.MAP32;
					*cast(uint*)&store_[Offset] = temp;
					stream_.put(store_[0..Offset + (uint).sizeof]);
				}
				return this;
			}
			private ref PackerImpl packNil()
			{
				stream_.put(Format.NIL);
				return this;
			}
		}
	}
}
alias Packer = PackerImpl!(Appender!(ubyte[]));
PackerImpl!Stream packer(Stream)(Stream stream, bool withFieldName = false)
{
	return typeof(return)(stream, withFieldName);
}
version (unittest)
{
	package 
	{
		import std.file;
		import core.stdc.string;
	}
	package template DefinePacker()
	{
		Packer packer;
	}
	package template DefineDictionalPacker()
	{
		Packer packer = Packer(false);
	}
}
