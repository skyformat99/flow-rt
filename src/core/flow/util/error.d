module flow.util.error;

/// mixin allowing to derrive from FlowError
mixin template error() {
    private import flow.util.templates : fqn;

    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.type);
    }
}

/// mixin allowing to derrive from FlowException
mixin template exception() {
    private import flow.data.engine : Data;
    private import flow.util.templates : fqn;

    override @property string type() {return fqn!(typeof(this));}

    Exception[] inner;

    this(string msg = string.init, Data d = null, Exception[] i = null) {
        super(msg != string.init ? msg : this.type);
        this.data = d;
        this.inner = i;
    }
}

/// smart error knowing its type
class FlowError : Error {
    /// type name
	abstract @property string type();

    /// ctor
    this(string msg) {super(msg);}
}

/// smart exception knowing its type and storing context data
class FlowException : Exception {
    private import flow.data.engine : Data;

    /// type name
	abstract @property string type();

    /// context data
    Data data;

    /// ctor
    this(string msg) {super(msg);}
}

/// thrown when hitting code which is not implemented yet
class NotImplementedError : FlowError {mixin error;}