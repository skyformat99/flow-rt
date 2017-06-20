module flow.example.base.trainingkicker.trainedkicker;
import flow.example.base.trainingkicker.signals;
import flow.example.base.simplekicker.kicker;

import std.uuid;

import flow.base.blocks, flow.base.signals, flow.base.interfaces;

class TrainedKickerContext : KickerContext
{
	mixin data;

    mixin field!(bool, "stop");
}

class TrainedKick : Tick
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
        this.send(new BallKicked);
    }
}

class TrainedReceipt : Tick, ISync
{
	mixin tick;

	override void run()
	{
        import flow.base.dev;

        auto c = this.entity.context.as!KickerContext;
        if(!this.entity.context.as!TrainedKickerContext.stop)
            this.ticker.next(fqn!WatchOut);
        else
        {
            c.done = true;
            this.send(new ReturnBall);
        }
    }
}

class Stop : Tick
{
	mixin tick;

	override void run()
	{
        import flow.base.dev;
        
        debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
            ~ ") stopped kicking", 1);
    }
}

bool canTrainedKick(Entity e, Signal s)
{
    auto c = e.context.as!KickerContext;
    auto acceptable = s.source.type == "flow.example.base.trainingkicker.trainedkicker.TrainedKicker";

    if(acceptable && !c.targetLocked)
    {
        c.targetLocked = true;
        return true;
    }
    else return false;
}

class TrainedKicker : Kicker
{
    mixin entity!(TrainedKickerContext);

    mixin listen!(fqn!(Ball),
        (e, s) => canAccept(e, s) ? new TrainedReceipt : null
    );

    mixin listen!(fqn!(Pong),
        (e, s) => canTrainedKick(e, s) ? new TrainedKick : null
    );

    mixin listen!(fqn!(StopKicking),
        (e, s) {
            e.context.as!TrainedKickerContext.stop = true;
            return new Stop;
        }
    );
}