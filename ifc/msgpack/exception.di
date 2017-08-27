// D import file generated from './msgpack/exception.d'
module msgpack.exception;
@trusted 
{
	class MessagePackException : Exception
	{
		pure this(string message)
		{
			super(message);
		}
	}
	class UnpackException : MessagePackException
	{
		this(string message)
		{
			super(message);
		}
	}
}
