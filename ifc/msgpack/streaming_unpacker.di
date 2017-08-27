// D import file generated from './msgpack/streaming_unpacker.d'
module msgpack.streaming_unpacker;
import msgpack.common;
import msgpack.attribute;
import msgpack.exception;
import msgpack.value;
import std.array;
import std.exception;
import std.range;
import std.stdio;
import std.traits;
import std.typecons;
import std.typetuple;
import std.container;
struct Unpacked
{
	import std.conv : text;
	Value value;
	alias value this;
@safe this(ref Value value)
	{
		this.value = value;
	}
	const nothrow @property @trusted bool empty();
	@property @trusted size_t length();
	@property ref @trusted Value front();
	@trusted void popFront();
	ref @trusted Value opIndex(size_t n);
	@trusted Value[] opSlice(size_t from, size_t to);
	@property @safe Unpacked save();
}
struct StreamingUnpacker
{
	private 
	{
		enum State 
		{
			HEADER = 0,
			BIN8 = 4,
			BIN16,
			BIN32,
			FLOAT = 10,
			DOUBLE,
			UINT8,
			UINT16,
			UINT32,
			UINT64,
			INT8,
			INT16,
			INT32,
			INT64,
			STR8 = 25,
			RAW16 = 26,
			RAW32,
			ARRAY16,
			ARRAY36,
			MAP16,
			MAP32,
			RAW,
			EXT8,
			EXT16,
			EXT32,
			EXT_DATA,
			REAL,
		}
		enum ContainerElement 
		{
			ARRAY_ITEM,
			MAP_KEY,
			MAP_VALUE,
		}
		static struct Context
		{
			static struct Container
			{
				ContainerElement type;
				Value value;
				Value key;
				size_t count;
			}
			State state;
			size_t trail;
			size_t top;
			Container[] stack;
		}
		Context context_;
		mixin InternalBuffer!();
		public 
		{
			@safe this(in ubyte[] target, in size_t bufferSize = 8192)
			{
				initializeBuffer(target, bufferSize);
				initializeContext();
			}
			@property @safe Unpacked unpacked();
			nothrow @safe void clear();
			@safe Unpacked purge();
			bool execute();
			int opApply(scope int delegate(ref Unpacked) dg);
			private nothrow @safe void initializeContext();
		}
	}
}
private @trusted 
{
	void callbackUInt(ref Value value, ulong number);
	void callbackInt(ref Value value, long number);
	void callbackFloat(ref Value value, real number);
	void callbackRaw(ref Value value, ubyte[] raw);
	void callbackExt(ref Value value, ubyte[] raw);
	void callbackArray(ref Value value, size_t length);
	void callbackMap(ref Value value, lazy size_t length);
	void callbackNil(ref Value value);
	void callbackBool(ref Value value, bool boolean);
}
