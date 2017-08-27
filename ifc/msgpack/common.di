// D import file generated from './msgpack/common.d'
module msgpack.common;
import msgpack.attribute;
import std.typetuple;
import std.traits;
version (Windows)
{
	package import core.sys.windows.winsock2;
}
else
{
	package import core.sys.posix.arpa.inet;
}
version (EnableReal)
{
	package enum EnableReal = true;
}
else
{
	package enum EnableReal = false;
}
static if ((real).sizeof == (double).sizeof)
{
	version = NonX86;
	package import std.numeric;
}
@trusted public 
{
	struct ExtValue
	{
		byte type;
		ubyte[] data;
	}
	enum Format : ubyte
	{
		UINT8 = 204,
		UINT16 = 205,
		UINT32 = 206,
		UINT64 = 207,
		INT8 = 208,
		INT16 = 209,
		INT32 = 210,
		INT64 = 211,
		FLOAT = 202,
		DOUBLE = 203,
		RAW = 160,
		RAW16 = 218,
		RAW32 = 219,
		BIN8 = 196,
		BIN16 = 197,
		BIN32 = 198,
		EXT = 212,
		EXT8 = 199,
		EXT16 = 200,
		EXT32 = 201,
		STR8 = 217,
		ARRAY = 144,
		ARRAY16 = 220,
		ARRAY32 = 221,
		MAP = 128,
		MAP16 = 222,
		MAP32 = 223,
		NIL = 192,
		TRUE = 195,
		FALSE = 194,
		REAL = 212,
	}
	package 
	{
		union _f
		{
			float f;
			uint i;
		}
		union _d
		{
			double f;
			ulong i;
		}
		union _r
		{
			real f;
			struct
			{
				ulong fraction;
				ushort exponent;
			}
		}
		enum RealSize = 10;
		enum isByte(T) = staticIndexOf!(Unqual!T, byte, ubyte) >= 0;
		template AsteriskOf(T)
		{
			static if (is(T P == U*, U))
			{
				enum AsteriskOf = "*" ~ AsteriskOf!U;
			}
			else
			{
				enum AsteriskOf = "";
			}
		}
		template SerializingMemberNumbers(Classes...)
		{
			static if (Classes.length == 0)
			{
				enum SerializingMemberNumbers = 0;
			}
			else
			{
				enum SerializingMemberNumbers = Filter!(isPackedField, Classes[0].tupleof).length + SerializingMemberNumbers!(Classes[1 .. $]);
			}
		}
		template SerializingClasses(T)
		{
			static if (is(T == Object))
			{
				static assert(false, "Object type serialization doesn't support yet. Please define toMsgpack/fromMsgpack and use cast");
			}
			else
			{
				alias SerializingClasses = TypeTuple!(Reverse!(Erase!(Object, BaseClassesTuple!T)), T);
			}
		}
		template getFieldName(Type, size_t i)
		{
			import std.conv : text;
			static assert(is(Unqual!Type == class) || is(Unqual!Type == struct), "Type must be class or struct: type = " ~ Type.stringof);
			static assert(i < Type.tupleof.length, text(Type.stringof, " has ", Type.tupleof.length, " attributes: given index = ", i));
			enum getFieldName = __traits(identifier, Type.tupleof[i]);
		}
		version (LittleEndian)
		{
			@trusted ushort convertEndianTo(size_t Bit, T)(in T value) if (Bit == 16)
			{
				return ntohs(cast(ushort)value);
			}
			@trusted uint convertEndianTo(size_t Bit, T)(in T value) if (Bit == 32)
			{
				return ntohl(cast(uint)value);
			}
			@trusted ulong convertEndianTo(size_t Bit, T)(in T value) if (Bit == 64)
			{
				return cast(ulong)value << 56 & 18374686479671623680LU | cast(ulong)value << 40 & 71776119061217280LU | cast(ulong)value << 24 & 280375465082880LU | cast(ulong)value << 8 & 1095216660480LU | cast(ulong)value >> 8 & 4278190080LU | cast(ulong)value >> 24 & 16711680LU | cast(ulong)value >> 40 & 65280LU | cast(ulong)value >> 56 & 255LU;
			}
			ubyte take8from(size_t bit = 8, T)(T value)
			{
				static if (bit == 8 || bit == 16 || bit == 32 || bit == 64)
				{
					return (cast(ubyte*)&value)[0];
				}
				else
				{
					static assert(false, bit.stringof ~ " is not support bit width.");
				}
			}
		}
		else
		{
			@safe ushort convertEndianTo(size_t Bit, T)(in T value) if (Bit == 16)
			{
				return cast(ushort)value;
			}
			@safe uint convertEndianTo(size_t Bit, T)(in T value) if (Bit == 32)
			{
				return cast(uint)value;
			}
			@safe ulong convertEndianTo(size_t Bit, T)(in T value) if (Bit == 64)
			{
				return cast(ulong)value;
			}
			ubyte take8from(size_t bit = 8, T)(T value)
			{
				static if (bit == 8)
				{
					return (cast(ubyte*)&value)[0];
				}
				else
				{
					static if (bit == 16)
					{
						return (cast(ubyte*)&value)[1];
					}
					else
					{
						static if (bit == 32)
						{
							return (cast(ubyte*)&value)[3];
						}
						else
						{
							static if (bit == 64)
							{
								return (cast(ubyte*)&value)[7];
							}
							else
							{
								static assert(false, bit.stringof ~ " is not support bit width.");
							}
						}
					}
				}
			}
		}
		T load16To(T)(ubyte[] buffer)
		{
			return cast(T)convertEndianTo!16(*cast(ushort*)buffer.ptr);
		}
		T load32To(T)(ubyte[] buffer)
		{
			return cast(T)convertEndianTo!32(*cast(uint*)buffer.ptr);
		}
		T load64To(T)(ubyte[] buffer)
		{
			return cast(T)convertEndianTo!64(*cast(ulong*)buffer.ptr);
		}
		version (D_Ddoc)
		{
			template InternalBuffer()
			{
				private 
				{
					ubyte[] buffer_;
					size_t used_;
					size_t offset_;
					size_t parsed_;
					bool hasRaw_;
					public 
					{
						nothrow @property @safe ubyte[] buffer();
						@safe void feed(in ubyte[] target);
						nothrow @safe void bufferConsumed(in size_t size);
						nothrow @safe void removeUnparsed();
						const nothrow @property @safe size_t size();
						const nothrow @property @safe size_t parsedSize();
						const nothrow @property @safe size_t unparsedSize();
						private @safe void initializeBuffer(in ubyte[] target, in size_t bufferSize = 8192);
					}
				}
			}
		}
		else
		{
			template InternalBuffer()
			{
				private 
				{
					ubyte[] buffer_;
					size_t used_;
					size_t offset_;
					size_t parsed_;
					bool hasRaw_;
					public 
					{
						nothrow @property @safe ubyte[] buffer()
						{
							return buffer_;
						}
						@safe void feed(in ubyte[] target)
						in
						{
							assert(target.length);
						}
						body
						{
							void expandBuffer(in size_t size);
							const size = target.length;
							if (buffer_.length - used_ < size)
								expandBuffer(size);
							buffer_[used_..used_ + size] = target[];
							used_ += size;
						}
						nothrow @safe void bufferConsumed(in size_t size)
						{
							if (used_ + size > buffer_.length)
								used_ = buffer_.length;
							else
								used_ += size;
						}
						nothrow @safe void removeUnparsed()
						{
							used_ = offset_;
						}
						const nothrow @property @safe size_t size()
						{
							return parsed_ - offset_ + used_;
						}
						const nothrow @property @safe size_t parsedSize()
						{
							return parsed_;
						}
						const nothrow @property @safe size_t unparsedSize()
						{
							return used_ - offset_;
						}
						private nothrow @safe void initializeBuffer(in ubyte[] target, in size_t bufferSize = 8192)
						{
							const size = target.length;
							buffer_ = new ubyte[](size > bufferSize ? size : bufferSize);
							used_ = size;
							buffer_[0..size] = target[];
						}
					}
				}
			}
		}
	}
}
