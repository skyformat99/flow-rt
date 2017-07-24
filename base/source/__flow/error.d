module __flow.error;

import __flow.data, __flow.util;

mixin template error() {
    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.type);
    }
}

mixin template exception() {
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

class FlowException : Exception {
	abstract @property string type();
    Data data;

    this(string msg) {super(msg);}
}

class WorkerError : FlowError {
    mixin error;
}

class NotImplementedError : FlowError {
    mixin error;
}

class ImplementationError : FlowError {
    mixin error;
}

class ParameterException : FlowException {
    mixin exception;
}

class UnsupportedObjectTypeException : FlowException {
    mixin exception;
}

class DataDamageException : FlowException {
    mixin exception;
}