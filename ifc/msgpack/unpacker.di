// D import file generated from './msgpack/unpacker.d'
module msgpack.unpacker;
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
private extern (C) Object _d_newclass(in ClassInfo);
struct Unpacker
{
	private 
	{
		static @system 
		{
			alias UnpackHandler = void delegate(ref Unpacker, void*);
			UnpackHandler[TypeInfo] unpackHandlers;
			public void registerHandler(T, alias Handler)()
			{
				unpackHandlers[typeid(T)] = delegate (ref Unpacker unpacker, void* obj)
				{
					Handler(unpacker, *cast(T*)obj);
				}
				;
			}
			public void register(T)()
			{
				unpackHandlers[typeid(T)] = delegate (ref Unpacker unpacker, void* obj)
				{
					unpacker.unpackObject(*cast(T*)obj);
				}
				;
			}
		}
		enum Offset = 1;
		mixin InternalBuffer!();
		bool withFieldName_;
		public 
		{
			this(in ubyte[] target, in size_t bufferSize = 8192, bool withFieldName = false)
			{
				initializeBuffer(target, bufferSize);
				withFieldName_ = withFieldName;
			}
			nothrow @safe void clear();
			ref Unpacker unpack(T)(ref T value) if (is(Unqual!T == bool))
			{
				canRead(Offset, 0);
				const header = read();
				switch (header)
				{
					case Format.TRUE:
					{
						value = true;
						break;
					}
					case Format.FALSE:
					{
						value = false;
						break;
					}
					default:
					{
						rollback(0, "bool", cast(Format)header);
					}
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (isUnsigned!T && !is(Unqual!T == enum))
			{
				canRead(Offset, 0);
				const header = read();
				if (0 <= header && header <= 127)
				{
					value = header;
				}
				else
				{
					switch (header)
					{
						case Format.UINT8:
						{
							canRead((ubyte).sizeof);
							value = read();
							break;
						}
						case Format.UINT16:
						{
							canRead((ushort).sizeof);
							auto us = load16To!ushort(read((ushort).sizeof));
							if (us > T.max)
								rollback((ushort).sizeof, T.stringof, Format.UINT16);
							value = cast(T)us;
							break;
						}
						case Format.UINT32:
						{
							canRead((uint).sizeof);
							auto ui = load32To!uint(read((uint).sizeof));
							if (ui > T.max)
								rollback((uint).sizeof, T.stringof, Format.UINT32);
							value = cast(T)ui;
							break;
						}
						case Format.UINT64:
						{
							canRead((ulong).sizeof);
							auto ul = load64To!ulong(read((ulong).sizeof));
							if (ul > T.max)
								rollback((ulong).sizeof, T.stringof, Format.UINT64);
							value = cast(T)ul;
							break;
						}
						default:
						{
							rollback(0, T.stringof, cast(Format)header);
						}
					}
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (isSigned!T && isIntegral!T && !is(Unqual!T == enum))
			{
				canRead(Offset, 0);
				const header = read();
				if (0 <= header && header <= 127)
				{
					value = cast(T)header;
				}
				else if (224 <= header && header <= 255)
				{
					value = -cast(T)-header;
				}
				else
				{
					switch (header)
					{
						case Format.UINT8:
						{
							canRead((ubyte).sizeof);
							auto ub = read();
							if (ub > T.max)
								rollback((ubyte).sizeof, T.stringof, Format.UINT8);
							value = cast(T)ub;
							break;
						}
						case Format.UINT16:
						{
							canRead((ushort).sizeof);
							auto us = load16To!ushort(read((ushort).sizeof));
							if (us > T.max)
								rollback((ushort).sizeof, T.stringof, Format.UINT16);
							value = cast(T)us;
							break;
						}
						case Format.UINT32:
						{
							canRead((uint).sizeof);
							auto ui = load32To!uint(read((uint).sizeof));
							if (ui > T.max)
								rollback((uint).sizeof, T.stringof, Format.UINT32);
							value = cast(T)ui;
							break;
						}
						case Format.UINT64:
						{
							canRead((ulong).sizeof);
							auto ul = load64To!ulong(read((ulong).sizeof));
							if (ul > T.max)
								rollback((ulong).sizeof, T.stringof, Format.UINT64);
							value = cast(T)ul;
							break;
						}
						case Format.INT8:
						{
							canRead((byte).sizeof);
							value = cast(byte)read();
							break;
						}
						case Format.INT16:
						{
							canRead((short).sizeof);
							auto s = load16To!short(read((short).sizeof));
							if (s < T.min || T.max < s)
								rollback((short).sizeof, T.stringof, Format.INT16);
							value = cast(T)s;
							break;
						}
						case Format.INT32:
						{
							canRead((int).sizeof);
							auto i = load32To!int(read((int).sizeof));
							if (i < T.min || T.max < i)
								rollback((int).sizeof, T.stringof, Format.INT32);
							value = cast(T)i;
							break;
						}
						case Format.INT64:
						{
							canRead((long).sizeof);
							auto l = load64To!long(read((long).sizeof));
							if (l < T.min || T.max < l)
								rollback((long).sizeof, T.stringof, Format.INT64);
							value = cast(T)l;
							break;
						}
						default:
						{
							rollback(0, T.stringof, cast(Format)header);
						}
					}
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (isSomeChar!T && !is(Unqual!T == enum))
			{
				static if (is(Unqual!T == char))
				{
					ubyte tmp;
				}
				else
				{
					static if (is(Unqual!T == wchar))
					{
						ushort tmp;
					}
					else
					{
						static if (is(Unqual!T == dchar))
						{
							uint tmp;
						}

					}
				}
				unpack(tmp);
				value = cast(T)tmp;
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (isFloatingPoint!T && !is(Unqual!T == enum))
			{
				canRead(Offset, 0);
				const header = read();
				switch (header)
				{
					case Format.FLOAT:
					{
						_f temp;
						canRead((uint).sizeof);
						temp.i = load32To!uint(read((uint).sizeof));
						value = temp.f;
						break;
					}
					case Format.DOUBLE:
					{
						static if (is(Unqual!T == float))
						{
							rollback(0, T.stringof, Format.DOUBLE);
						}

						_d temp;
						canRead((ulong).sizeof);
						temp.i = load64To!ulong(read((ulong).sizeof));
						value = temp.f;
						break;
					}
					case Format.REAL:
					{
						static if (!EnableReal)
						{
							rollback(0, "real is disabled", Format.REAL);
						}
						else
						{
							static if (is(Unqual!T == float) || is(Unqual!T == double))
							{
								rollback(0, T.stringof, Format.REAL);
							}

							canRead(RealSize);
							version (NonX86)
							{
								CustomFloat!80 temp;
								const frac = load64To!ulong(read((ulong).sizeof));
								const exp = load16To!ushort(read((ushort).sizeof));
								temp.significand = frac;
								temp.exponent = exp & 32767;
								temp.sign = exp & 32768 ? true : false;
								value = temp.get!real;
							}
							else
							{
								_r temp;
								temp.fraction = load64To!(typeof(temp.fraction))(read(temp.fraction.sizeof));
								temp.exponent = load16To!(typeof(temp.exponent))(read(temp.exponent.sizeof));
								value = temp.f;
							}
						}
						break;
					}
					default:
					{
						rollback(0, T.stringof, cast(Format)header);
					}
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (is(Unqual!T == enum))
			{
				OriginalType!T temp;
				unpack(temp);
				value = cast(T)temp;
				return this;
			}
			ref Unpacker unpack(T)(T value) if (isPointer!T)
			{
				static if (is(Unqual!T == void*))
				{
					enforce(value !is null, "Can't deserialize void type");
					unpackNil(value);
				}
				else
				{
					if (checkNil())
						unpackNil(value);
					else
						enforce(value !is null, T.stringof ~ " is null pointer");
					unpack(mixin(AsteriskOf!T ~ "value"));
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T value) if (is(T == ExtValue))
			{
				canRead(Offset, 0);
				const header = read();
				if (header >= Format.EXT && header <= Format.EXT + 4)
				{
					const length = 2 ^^ (header - Format.EXT);
					canRead(1 + length);
					value.type = read();
					value.data = read(length);
					return this;
				}
				uint length;
				switch (header)
				{
					with (Format)
					{
						case EXT8:
						{
							canRead(1);
							length = read();
							break;
						}
						case EXT16:
						{
							canRead(2);
							length = load16To!ushort(read(2));
							break;
						}
						case EXT32:
						{
							canRead(4);
							length = load32To!uint(read(4));
							break;
						}
						default:
						{
							rollback(0, T.stringof, cast(Format)header);
						}
					}
				}
				canRead(1 + length);
				value.type = read();
				value.data = read(length);
				return this;
			}
			ref Unpacker unpack(Types...)(ref Types objects) if (Types.length > 1)
			{
				foreach (i, T; Types)
				{
					unpack!T(objects[i]);
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T array) if ((isArray!T || isInstanceOf!(Array, T)) && !is(Unqual!T == enum))
			{
				alias U = typeof(T.init[0]);
				@safe size_t beginRaw();
				if (checkNil())
				{
					static if (isStaticArray!T)
					{
						onInvalidType("static array", Format.NIL);
					}
					else
					{
						return unpackNil(array);
					}
				}
				static if (isByte!U || isSomeChar!U)
				{
					auto length = beginRaw();
				}
				else
				{
					auto length = beginArray();
				}
				if (length > buffer_.length)
				{
					import std.conv : text;
					throw new MessagePackException(text("Invalid array size in byte stream: Length (", length, ") is larger than internal buffer size (", buffer_.length, ")"));
				}
				static if (isByte!U || isSomeChar!U)
				{
					auto offset = calculateSize!true(length);
					if (length == 0)
						return this;
					static if (isStaticArray!T)
					{
						if (length != array.length)
							rollback(offset, "static array was given but the length is mismatched");
					}

					canRead(length, offset + Offset);
					static if (isStaticArray!T)
					{
						array[] = (cast(U[])read(length))[0..T.length];
					}
					else
					{
						array = cast(T)read(length);
					}
					static if (isDynamicArray!T)
					{
						hasRaw_ = true;
					}

				}
				else
				{
					if (length == 0)
						return this;
					static if (isStaticArray!T)
					{
						if (length != array.length)
							rollback(calculateSize(length), "static array was given but the length is mismatched");
					}
					else
					{
						array.length = length;
					}
					foreach (i; 0 .. length)
					{
						unpack(array[i]);
					}
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T array) if (isAssociativeArray!T)
			{
				alias K = typeof(T.init.keys[0]);
				alias V = typeof(T.init.values[0]);
				if (checkNil())
					return unpackNil(array);
				auto length = beginMap();
				if (length == 0)
					return this;
				foreach (i; 0 .. length)
				{
					K k;
					unpack(k);
					V v;
					unpack(v);
					array[k] = v;
				}
				return this;
			}
			ref Unpacker unpack(T, Args...)(ref T object, auto ref Args args) if (is(Unqual!T == class))
			{
				if (checkNil())
					return unpackNil(object);
				if (object is null)
				{
					static if (Args.length == 0)
					{
						static if (__traits(compiles, ()
						{
							new T;
						}
						))
						{
							object = new T;
						}
						else
						{
							object = cast(T)_d_newclass(T.classinfo);
						}
					}
					else
					{
						static if (__traits(compiles, ()
						{
							new T(args);
						}
						))
						{
							object = new T(args);
						}
						else
						{
							throw new MessagePackException("Don't know how to construct class type '" ~ Unqual!T.stringof ~ "' with argument types '" ~ Args.stringof ~ "'.");
						}
					}
				}
				static if (hasMember!(T, "fromMsgpack"))
				{
					static if (__traits(compiles, ()
					{
						object.fromMsgpack(this, withFieldName_);
					}
					))
					{
						object.fromMsgpack(this, withFieldName_);
					}
					else
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
				}
				else
				{
					if (auto handler = object.classinfo in unpackHandlers)
					{
						(*handler)(this, cast(void*)&object);
						return this;
					}
					if (T.classinfo !is object.classinfo)
					{
						throw new MessagePackException("Can't unpack derived class through reference to base class.");
					}
					unpackObject(object);
				}
				return this;
			}
			ref Unpacker unpack(T)(ref T object) if (is(Unqual!T == struct) && !is(Unqual!T == ExtValue))
			{
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
					if (auto handler = typeid(T) in unpackHandlers)
					{
						(*handler)(this, cast(void*)&object);
						return this;
					}
					size_t length = withFieldName_ ? beginMap() : beginArray();
					if (length == 0)
						return this;
					static if (isTuple!T)
					{
						if (length != T.Types.length)
							rollback(calculateSize(length), "the number of tuple fields is mismatched");
						foreach (i, Type; T.Types)
						{
							unpack(object.field[i]);
						}
					}
					else
					{
						if (length != SerializingMemberNumbers!T)
							rollback(calculateSize(length), "the number of struct fields is mismatched");
						if (withFieldName_)
						{
							foreach (i, member; object.tupleof)
							{
								static if (isPackedField!(T.tupleof[i]))
								{
									string fieldName;
									unpack(fieldName);
									if (fieldName == getFieldName!(T, i))
									{
										unpack(object.tupleof[i]);
									}
									else
									{
										assert(false, "Invalid field name: '" ~ fieldName ~ "', expect '" ~ getFieldName!(T, i) ~ "'");
									}
								}

							}
						}
						else
						{
							foreach (i, member; object.tupleof)
							{
								static if (isPackedField!(T.tupleof[i]))
								{
									unpack(object.tupleof[i]);
								}

							}
						}
					}
				}
				return this;
			}
			void unpackObject(T)(ref T object) if (is(Unqual!T == class))
			{
				alias Classes = SerializingClasses!T;
				size_t length = withFieldName_ ? beginMap() : beginArray();
				if (length == 0)
					return ;
				if (length != SerializingMemberNumbers!Classes)
					rollback(calculateSize(length), "the number of class fields is mismatched");
				if (withFieldName_)
				{
					foreach (_; 0 .. length)
					{
						string fieldName;
						unpack(fieldName);
						foreach (Class; Classes)
						{
							Class obj = cast(Class)object;
							foreach (i, member; obj.tupleof)
							{
								static if (isPackedField!(Class.tupleof[i]))
								{
									if (fieldName == getFieldName!(Class, i))
									{
										unpack(obj.tupleof[i]);
										goto endLoop;
									}
								}

							}
						}
						assert(false, "Invalid field name: '" ~ fieldName ~ "' ");
						endLoop:
						continue;
					}
				}
				else
				{
					foreach (Class; Classes)
					{
						Class obj = cast(Class)object;
						foreach (i, member; obj.tupleof)
						{
							static if (isPackedField!(Class.tupleof[i]))
							{
								unpack(obj.tupleof[i]);
							}

						}
					}
				}
			}
			ref Unpacker unpackArray(Types...)(ref Types objects)
			{
				auto length = beginArray();
				if (length != Types.length)
					rollback(calculateSize(length), "the number of deserialized objects is mismatched");
				foreach (i, T; Types)
				{
					unpack(objects[i]);
				}
				return this;
			}
			ref Unpacker unpackMap(Types...)(ref Types objects)
			{
				static assert(Types.length % 2 == 0, "The number of arguments must be even");
				auto length = beginMap();
				if (length != Types.length / 2)
					rollback(calculateSize(length), "the number of deserialized objects is mismatched");
				foreach (i, T; Types)
				{
					unpack(objects[i]);
				}
				return this;
			}
			@safe size_t beginArray();
			@safe size_t beginMap();
			ref Unpacker unpackExt(ref byte type, ref ubyte[] data);
			int scan(Types...)(scope int delegate(ref Types) dg)
			{
				return opApply!Types(delegate int(ref Types objects)
				{
					return dg(objects);
				}
				);
			}
			int opApply(Types...)(scope int delegate(ref Types) dg)
			{
				int result;
				while (used_ - offset_)
				{
					auto length = beginArray();
					if (length != Types.length)
						rollback(calculateSize(length), "the number of deserialized objects is mismatched");
					Types objects;
					foreach (i, T; Types)
					{
						unpack(objects[i]);
					}
					result = dg(objects);
					if (result)
						return result;
				}
				return result;
			}
			private 
			{
				ref @safe Unpacker unpackNil(T)(ref T value)
				{
					canRead(Offset, 0);
					const header = read();
					if (header == Format.NIL)
						value = null;
					else
						rollback(0, "nil", cast(Format)header);
					return this;
				}
				@safe bool checkNil();
				size_t calculateSize(bool rawType = false)(in size_t length)
				{
					static if (rawType)
					{
						return length < 32 ? 0 : length < 65536 ? (ushort).sizeof : (uint).sizeof;
					}
					else
					{
						return length < 16 ? 0 : length < 65536 ? (ushort).sizeof : (uint).sizeof;
					}
				}
				@safe void canRead(in size_t size, in size_t offset = Offset);
				nothrow @safe ubyte read();
				nothrow @safe ubyte[] read(in size_t size);
				@safe void rollback(in size_t size, in string reason);
				@safe void rollback(in size_t size, in string expected, in Format actual);
			}
		}
	}
}
private 
{
	pure @safe void onInvalidType(in string reason);
	pure @safe void onInvalidType(in string expected, in Format actual);
}
