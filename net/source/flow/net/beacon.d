module flow.net.beacon;

import std.uuid, std.array, std.string, std.datetime, std.conv, std.algorithm.searching, std.algorithm.iteration, std.file;

import flow.base.interfaces, flow.base.blocks;
import flow.base.data, flow.base.signals;

class StartBeacon : Unicast{mixin signal!();}
class StopBeacon : Unicast{mixin signal!();}

class BeaconContext : Data
{
	mixin data;

    mixin field!(string, "error");
    mixin list!(BeaconSessionInfo, "sessions");
    mixin field!(string, "defSession");
}

class BeaconSessionRequestData : Data
{
	mixin data;

    mixin list!(string, "listenings");
}

class BeaconSessionContext : Data
{
	mixin data;

    mixin field!(EntityPtr, "beacon");
}

class BeaconSessionListening : IdData
{
    mixin data;

    mixin field!(string, "signal");
    mixin list!(UUID, "sources");
}

class BeaconSessionInfo : Data
{
	mixin data;

    mixin field!(EntityPtr, "session");
    mixin field!(DateTime, "lastActivity");
    mixin list!(BeaconSessionListening, "listenings");
    mixin list!(WrappedSignal, "inQueue");
}

class PullWrappedSignal : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!WrappedSignal;
        auto c = this.entity.context.as!BeaconContext;

        if(c.sessions.array.any!(i=>i.session.id == s.source.id))
        {
            auto info = c.sessions.array.filter!(i=>i.session.id == s.source.id).front;
            auto session = this.entity.hull.get(s.source.id);
            if(this.entity.hull.tracing && s.as!IStealth is null)
            {
                auto td = new TraceTickData;
                auto ts = new TraceBeginTick;
                ts.type = ts.dataType;
                ts.source = session.info.ptr;
                ts.data = td;
                ts.data.id = session.id;
                ts.data.time = Clock.currTime.toUTC();
                ts.data.entityType = session.__fqn;
                ts.data.entityId = session.id;
                ts.data.tick = session.__fqn;
                this.entity.hull.send(ts);
            }

            info.inQueue.put(s);
        }
        else // this session should not exist, so kill it
        {
            this.entity.hull.remove(s.source.id);
        }
    }
}

class PushWrappedSignal : Tick, IStealth
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!BeaconSessionContext;
        auto wd = new WrappedSignalData;
        wd.signal = this.trigger.json;
        auto ws = new WrappedSignal;
        ws.data = wd;
        this.send(ws, c.beacon);
    }
}

class BeaconAlreadyStarted : Tick
{
	mixin tick;

	override void run()
	{
    }
}

class BeaconAlreadyStopped : Tick
{
	mixin tick;

	override void run()
	{
    }
}

class BeaconSession : Entity, IQuiet
{
    mixin entity!(BeaconSessionContext);

    /*mixin listen!(fqn!WrappedSignal,
        (e, s) => new PushWrappedSignal
    );*/
}

class Beacon : Entity, IStealth, IQuiet
{
    mixin entity;

    mixin listen!(fqn!StartBeacon,
        (e, s) => e.as!Beacon.onStartBeacon(s)
    );
    
    mixin listen!(fqn!WrappedSignal,
        (e, s) => new PullWrappedSignal
    ); 

    mixin listen!(fqn!StopBeacon,
        (e, s) => e.as!Beacon.onStopBeacon(s)
    );

    protected Object onStartBeacon(Signal s) {return null;} 
    protected Object onStopBeacon(Signal s) {return null;} 
}
