module flow.ipc.nanomsg;

import core.sync.rwmutex;
import core.thread;
import flow.core;
import flow.data;
import deimos.nanomsg.nn;
import deimos.nanomsg.pubsub;
import std.string;
import std.array;

/// at linking something bad is happening if "Data" symbol is not used in shared library
private static import flow.data.engine; class __Foo : flow.data.engine.Data {mixin flow.data.engine.data;}

/*class MeshJunctionInfo : JunctionInfo {
    import flow.data;

    mixin data;

    mixin field!(string, "addr");
}

class MeshJunctionMeta : JunctionMeta {
    import flow.data;

    mixin data;

    mixin field!(string[], "known");
}

/// junction allowing direct signalling between spaces hosted in same process
class MeshJunction : Junction {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import std.uuid : UUID;

    private ReadWriteMutex lock;
    private MeshJunctionInfo[string] others;

    override @property MeshJunctionMeta meta() {
        import flow.util : as;
        return super.meta.as!MeshJunctionMeta;
    }

    override @property string[] list() {
        return others.keys;
    }

    /// ctor
    this() {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        super();
    }

    override bool up() {
        import flow.util : as;

        synchronized(lock.writer) {
            // TODO CONNECT
        }

        return true;
    }

    override void down() {
        synchronized(lock.writer) {
            // TODO DISCONNECT

            foreach(j; this.others.keys)
                this.others.remove(j);
        }
    }

    override Channel get(string space) {
        return space in this.others
        ? new MeshChannel(this, this.others[space])
        : null;
    }
}

class MeshChannel : Channel {
    private MeshJunction own;
    private MeshJunctionInfo _other;

    override @property JunctionInfo other() {return this._other;}

    this(MeshJunction own, MeshJunctionInfo other) {
        this.own = own;
        this._other = other;
    }

    override bool transport(ubyte[] p) {
        import flow.util : as;

        // TODO TRANSMIT

        return false;
    }
}*/

/*class NanoMsgConnector : Connector {
    private ReadWriteMutex lock;
    private Thread listener;
    private int pubSock;
    private int[string] subSock;

    protected override void start() {
        // create publishing socket
        this.pubSock = nn_socket (AF_SP, NN_PUB);

        // initialize mutex
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        // create listener thread
        this.listener = new Thread(&listen);
        this.listener.start();
    }

    private void listen() {
        while(this.listener !is null) {
            synchronized(this.lock.reader)
                foreach(s, sock; this.subSock) {
                    ubyte *buf = cast(ubyte*)0;
                    int bytes = nn_recv (sock, &buf, NN_MSG, NN_DONTWAIT);
                    if(bytes > 0) {
                        this.junction.ship(buf[0..bytes]);
                    }
                    nn_freemsg (buf);
                }
        }
    }

    protected override void stop() {
        // close publishing socket
        nn_close(this.pubSock);

        // shut down listener
        auto l = this.listener;
        this.listener = null;
        l.join();

        // hide all exposed
        foreach(s; this.subSock.keys.array)
            this.hide(s);

        this.lock = null;
    }
    protected override void expose(string space) {
        auto dst = cast(ubyte[])space;
        if(space !in this.subSock) {
            synchronized(this.lock.writer) {
                int sock = nn_socket (AF_SP, NN_SUB);
                if(nn_setsockopt(sock, NN_SUB, NN_SUB_SUBSCRIBE, dst.ptr, 0) >= 0) {
                    this.subSock[space] = sock;
                } else {*//*TODO throw exception*//*}
            }
        }
    }
    protected override void hide(string space) {
        if(space in this.subSock)
            synchronized(this.lock.writer) {
                nn_close(this.subSock[space]);
                this.subSock.remove(space);
            }
    }

    protected override void ship(string space, ubyte[] bin, ubyte[] sig) {
        auto msg = cast(ubyte[])space~sig~bin;

        nn_send(this.pubSock, msg.ptr, 0, 0);
    }
}*/