// D import file generated from './msgpack/buffer.d'
module msgpack.buffer;
import std.range;
version (Posix)
{
	import core.sys.posix.sys.uio : iovec;
}
else
{
	struct iovec
	{
		void* iov_base;
		size_t iov_len;
	}
}
struct RefBuffer
{
	private 
	{
		static struct Chunk
		{
			ubyte[] data;
			size_t used;
		}
		immutable size_t Threshold;
		immutable size_t ChunkSize;
		Chunk[] chunks_;
		size_t index_;
		iovec[] vecList_;
		public 
		{
			@safe this(in size_t threshold, in size_t chunkSize = 8192)
			{
				Threshold = threshold;
				ChunkSize = chunkSize;
				chunks_.length = 1;
				chunks_[index_].data.length = chunkSize;
			}
			nothrow @property @safe ubyte[] data();
			nothrow @property ref @safe iovec[] vector();
			@safe void put(in ubyte value);
			@safe void put(in ubyte[] value);
			private 
			{
				@trusted void putRef(in ubyte[] value);
				@trusted void putCopy(in ubyte[] value);
			}
		}
	}
}
