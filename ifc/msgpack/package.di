// D import file generated from './msgpack/package.d'
module msgpack;
public 
{
	import msgpack.common;
	import msgpack.attribute;
	import msgpack.buffer;
	import msgpack.exception;
	import msgpack.packer;
	import msgpack.unpacker;
	import msgpack.streaming_unpacker;
	import msgpack.register;
	import msgpack.value;
	@trusted 
	{
		ubyte[] pack(bool withFieldName = false, Args...)(in Args args)
		{
			auto packer = Packer(withFieldName);
			static if (Args.length == 1)
			{
				packer.pack(args[0]);
			}
			else
			{
				packer.packArray(args);
			}
			return packer.stream.data;
		}
		Unpacked unpack(in ubyte[] buffer);
		void unpack(bool withFieldName = false, Args...)(in ubyte[] buffer, ref Args args)
		{
			auto unpacker = Unpacker(buffer, buffer.length, withFieldName);
			static if (Args.length == 1)
			{
				unpacker.unpack(args[0]);
			}
			else
			{
				unpacker.unpackArray(args);
			}
		}
		Type unpack(Type, bool withFieldName = false)(in ubyte[] buffer)
		{
			auto unpacker = Unpacker(buffer, buffer.length, withFieldName);
			Type result;
			unpacker.unpack(result);
			return result;
		}
		template MessagePackable(Members...)
		{
			static if (Members.length == 0)
			{
				const void toMsgpack(Packer)(ref Packer packer, bool withFieldName = false)
				{
					if (withFieldName)
					{
						packer.beginMap(this.tupleof.length);
						foreach (i, member; this.tupleof)
						{
							packer.pack(getFieldName!(typeof(this), i));
							packer.pack(member);
						}
					}
					else
					{
						packer.beginArray(this.tupleof.length);
						foreach (member; this.tupleof)
						{
							packer.pack(member);
						}
					}
				}
				void fromMsgpack(Value value)
				{
					if (value.type != Value.Type.array)
						throw new MessagePackException("Value must be an Array type");
					if (value.via.array.length != this.tupleof.length)
						throw new MessagePackException("The size of deserialized value is mismatched");
					foreach (i, member; this.tupleof)
					{
						this.tupleof[i] = value.via.array[i].as!(typeof(member));
					}
				}
				void fromMsgpack(ref Unpacker unpacker)
				{
					auto length = unpacker.beginArray();
					if (length != this.tupleof.length)
						throw new MessagePackException("The size of deserialized value is mismatched");
					foreach (i, member; this.tupleof)
					{
						unpacker.unpack(this.tupleof[i]);
					}
				}
			}
			else
			{
				const void toMsgpack(Packer)(ref Packer packer, bool withFieldName = false)
				{
					if (withFieldName)
					{
						packer.beginMap(Members.length);
						foreach (member; Members)
						{
							packer.pack(member);
							packer.pack(mixin(member));
						}
					}
					else
					{
						packer.beginArray(Members.length);
						foreach (member; Members)
						{
							packer.pack(mixin(member));
						}
					}
				}
				void fromMsgpack(Value value)
				{
					if (value.type != Value.Type.array)
						throw new MessagePackException("Value must be an Array type");
					if (value.via.array.length != Members.length)
						throw new MessagePackException("The size of deserialized value is mismatched");
					foreach (i, member; Members)
					{
						mixin(member ~ "= value.via.array[i].as!(typeof(" ~ member ~ "));");
					}
				}
				void fromMsgpack(ref Unpacker unpacker)
				{
					auto length = unpacker.beginArray();
					if (length != Members.length)
						throw new MessagePackException("The size of deserialized value is mismatched");
					foreach (member; Members)
					{
						unpacker.unpack(mixin(member));
					}
				}
			}
		}
	}
}
