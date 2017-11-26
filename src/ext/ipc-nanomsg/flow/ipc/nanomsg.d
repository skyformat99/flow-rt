module flow.ipc.nanomsg;

import flow.core;

/// at linking something bad is happening if "Data" symbol is not used in shared library
private static import flow.data.engine; class Foo : flow.data.engine.Data {mixin flow.data.engine.data;}

class NanoMsgConnectorConfig : ConnectorConfig {
    import flow.data;

    mixin data;

    mixin field!(string, "bla");
}

class NanoMsgConnector : Connector {    
    protected override void start() {}
    protected override void stop() {}
    protected override bool canSend(Signal s) {return false;}
    protected override bool send(string dst, ubyte[] bin, ubyte[] sig) {return false;}
}