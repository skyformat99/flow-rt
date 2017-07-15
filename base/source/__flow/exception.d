module __flow.exception;
import __flow.data, __flow.type;

import std.traits;

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
    override @property string __fqn() {return fullyQualifiedName!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.__fqn);
    }
}

mixin template TException() {
    override @property string __fqn() {return fullyQualifiedName!(typeof(this));}

    List!Exception inner;

    this(string msg = string.init, Data d = null, List!Exception i = null) {
        super(msg != string.init ? msg : this.__fqn);
        this.data = d;
        this.inner = i;
    }
}

class FlowError : Error, __IFqn {
	abstract @property string __fqn();

    this(string msg) {super(msg);}
}

class FlowException : Error, __IFqn {
	abstract @property string __fqn();
    Data data;

    this(string msg) {super(msg);}
}

class WorkerError : FlowError {
    mixin TError;
}

class NotImplementedError : FlowError {
    mixin TError;
}

class ImplementationError : FlowError {
    mixin TError;
}

class ParameterException : FlowException {
    mixin TException;
}

class UnsupportedObjectTypeException : FlowException {
    mixin TException;
}

class DataDamageException : FlowException {
    mixin TException;
}

class TickException : FlowException {
    mixin TException;
}