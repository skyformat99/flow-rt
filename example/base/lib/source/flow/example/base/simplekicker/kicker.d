module flow.example.base.simplekicker.kicker;

import flow.base.blocks, flow.base.signals, flow.base.interfaces;

class Ball : Unicast{mixin signal!();}

class KickerContext : Data
{
	mixin data;

    mixin field!(uint, "times");
    mixin field!(uint, "counter");
    mixin field!(bool, "done");
    mixin field!(bool, "targetLocked");
}

class WatchOut : Tick
{
	mixin tick;

	override void run()
	{
        import flow.base.signals;

        auto c = this.entity.context.as!KickerContext;
        c.targetLocked = false;
        this.send(new Ping);
    }
}

class Receipt : Tick, ISync
{
	mixin tick;

	override void run()
	{
        import std.conv;
        import flow.base.dev;

        auto c = this.entity.context.as!KickerContext;
        if(c.counter < c.times)
            this.ticker.next(fqn!WatchOut);
        else c.done = true;
    }
}

class Kick : Tick
{
	mixin tick;

	override void run()
	{
        import std.conv;
        import flow.base.dev;

        auto c = this.entity.context.as!KickerContext;

        c.counter = c.counter + 1;
        debugMsg(this.entity.id.toString ~ " kicked "
            ~c.counter.to!string ~ " time(s)", 1);
                
        this.answer(new Ball);
    }
}

bool canKick(Entity e, Signal s)
{
    auto c = e.context.as!KickerContext;
    auto acceptable = s.source.type == "flow.example.base.simplekicker.kicker.Kicker";

    if(acceptable && !c.targetLocked)
    {
        c.targetLocked = true;
        return true;
    }
    else return false;
}

bool canAccept(Entity e, Signal s)
{
    return s.source is null || !s.source.identWith(e);
}

class Kicker : Entity
{
    mixin entity!(KickerContext);

    mixin listen!(fqn!(Ball),
        (e, s) => canAccept(e, s) ? new Receipt : null
    );
    
    mixin listen!(fqn!(Pong),
        (e, s) => canKick(e, s) ? new Kick : null
    );
}