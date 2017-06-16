module flow.flow.exception;

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
        ptressException, HostException, SocketException, ... (std.socket)
*/

class NotImplementedError : Error
{
    this() { super("");}
}

class UnsupportedObjectTypeException : Exception
{
    this() { super("");}
}