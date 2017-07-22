module __flow.error;

import __flow.data, __flow.util;

mixin template TError() {
    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.type);
    }
}

mixin template TException() {
    override @property string type() {return fqn!(typeof(this));}

    Exception[] inner;

    this(string msg = string.init, Data d = null, Exception[] i = null) {
        super(msg != string.init ? msg : this.type);
        this.data = d;
        this.inner = i;
    }
}

class FlowError : Error {
	abstract @property string type();

    this(string msg) {super(msg);}
}

class FlowException : Error {
	abstract @property string type();
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