module __flow.exception, __flow.data;

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

mixin template TError() {
    @property string __fqn() {return fullyQualifiedName!(typeof(this));}

    this() { super(this.__fqn); }
}

mixin template TException(T = void) if(is(T == void) || is(T : Data)) {
    @property string __fqn() {return fullyQualifiedName!(typeof(this));}

    static if(!is(T == void))
        T data;
    else
        Data data;

    this() { super(this.__fqn); }
}

class FlowError : Error, __IFqn {
	abstract @property string __fqn();
}

class FlowException : Error, __IFqn {
	abstract @property string __fqn();
}

class NotImplementedError : FlowError {
    this() { super("");}
}

class ParameterException : FlowException {
    this(string msg) { super(msg);}
}

class UnsupportedObjectTypeException : Exception, __IFqn {
	abstract @property string __fqn();
    this(string type = "") { super(type);}
}