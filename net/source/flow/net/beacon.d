module flow.net.beacon;

import std.uuid, std.array, std.string, std.datetime, std.conv, std.algorithm.searching, std.algorithm.iteration, std.file;

import flow.base.interfaces, flow.base.blocks;
import flow.base.data, flow.base.signals;

class StartBeacon : Unicast{mixin signal!();}
class StopBeacon : Unicast{mixin signal!();}

class BeaconContext : Data {
	mixin data;

    mixin field!(string, "error");
    mixin list!(BeaconSessionInfo, "sessions");
    mixin field!(string, "defSession");
}

class BeaconSessionContext : Data {
	mixin data;

    mixin field!(EntityPtr, "beacon");
}

/*class BeaconSessionListening : IdData {
    mixin data;

    mixin field!(string, "signal");
    mixin list!(UUID, "sources");
}*/

class BeaconSessionInfo : Data {
	mixin data;

    mixin field!(EntityPtr, "session");
    mixin field!(DateTime, "lastActivity");
    //mixin list!(BeaconSessionListening, "listenings");
    mixin list!(string, "signals");
    mixin list!(WrappedSignal, "incoming");
}

class Read : Tick {
    mixin tick;

    override void run() {
        throw new ImplementationError("beacon needs to listen to WrappedSignal cominf from a session");
    }
}

class Incoming : Tick, IStealth {
	mixin tick;

	override void run() {
        auto c = this.context.as!BeaconSessionContext;
        auto wd = new WrappedSignalData;
        wd.signal = this.signal.json;
        auto ws = new WrappedSignal;
        ws.data = wd;
        this.send(ws, c.beacon);
    }
}

class BeaconSession : Entity {
    mixin entity;

    mixin listen!(fqn!WrappedSignal, fqn!Publish);
}

class Beacon : Entity, IStealth {
    mixin entity;
    
    mixin listen!(fqn!WrappedSignal, fqn!Read);
}
