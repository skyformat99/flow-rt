// D import file generated from './msgpack/register.d'
module msgpack.register;
import msgpack.packer;
import msgpack.unpacker;
import std.array;
void registerPackHandler(T, alias Handler, Stream = Appender!(ubyte[]))()
{
	PackerImpl!Stream.registerHandler!(T, Handler);
}
void registerUnpackHandler(T, alias Handler)()
{
	Unpacker.registerHandler!(T, Handler);
}
void registerClass(T, Stream = Appender!(ubyte[]))()
{
	PackerImpl!Stream.register!T;
	Unpacker.register!T;
}
