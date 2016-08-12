module flowbase.type.types;
import flowbase.type.meta;
import flowbase.type.signals;
import flowbase.type.interfaces;

import std.uuid;
import std.traits;
import std.range.interfaces;
import core.exception;

import flowbase.data.interfaces;

/* exception handling example
try {
    throw new Exception("error message");
} catch (Exception error) {
    writefln("Error catched: %s", error.msg);
} finally {
    writefln("in finaly block");
}
*/

/* exception/error overview
Throwable
    Error
        AssertError
        FinalizeError
        HiddenFuncError
        InvalidMemoryOperationError
        OutOfMemoryError
        RangeError
        SwitchError
    Exception
        ErrnoException
        UnicodeException
        FileException (std.file)
        ProcessException (std.process)
        RegexException (std.regex)
        DateTimeException (std.datetime)
        TimeException (core.time)
        StdioException (std.stdio)
        StringException (std.string)
        AddressException, HostException, SocketException, ... (std.socket)
*/

class NotImplementedError : Error
{
    this()
    {
        super("");
    }
}

class SignalArgs
{
}

/// signal arguents allowing cancelation
class CancelableSignalArgs : SignalArgs
{
	bool cancel = false;
}

/// mask scalar, uuid and string types into reference types which are N
class Ref(T) if (isScalarType!T || is(T == UUID) || is(T == string))
{
	T value;

	alias value this;

	this(T value)
	{
		this.value = value;
	}
}

/** offers an easy to use .NET like list of elements implementing notifications when collection changes
    MARKED FOR REFRACTORING
*/
class List(E) : IList!E
{
    mixin TInputRangeOfList!E;
    mixin TForwardRangeOfList!E;
    mixin TBidirectionalRangeOfList!E;
    mixin TRandomAccessFiniteOfList!E;
    mixin TOutputRangeOfList!E;
    mixin TEnumerableOfList!E;
    mixin TCollectionOfList!E;
    mixin TList!E;
}

class ReadonlyList(E) : IReadonlyList!E
{
    mixin TInputRangeOfList!E;
    mixin TForwardRangeOfList!E;
    mixin TBidirectionalRangeOfList!E;
    mixin TRandomAccessFiniteOfList!E;
    mixin TEnumerableOfList!E;
    mixin TList!E;
}

class DataList(E) : IDataList!E
{
    mixin TInputRangeOfList!E;
    mixin TForwardRangeOfList!E;
    mixin TBidirectionalRangeOfList!E;
    mixin TRandomAccessFiniteOfList!E;
    mixin TOutputRangeOfList!E;
    mixin TEnumerableOfList!E;
    mixin TCollectionOfList!E;
    mixin TList!E;
}
