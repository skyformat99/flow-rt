module flow.example.base.trainingkicker.trainer;
import flow.example.base.trainingkicker.signals;
import flow.example.base.simplekicker.kicker;

import std.uuid;

import flow.base.blocks;

class TrainerContext : Data
{
	mixin data;

    mixin field!(uint, "counter");
    mixin field!(bool, "ballMissing");
    mixin field!(int, "expectedKicks");
}

class ListenToTheWhispering : Tick
{
	mixin tick;

	override void run()
	{
        import flow.base.dev;

        auto c = this.entity.context.as!TrainerContext;
        auto s = this.trigger.as!Whisper;
        debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
            ~ ") was touched by god and throws ball to kicker("~s.data.type~", "~s.data.id.toString~")", 1);
        
        this.send(new Ball, s.data);
        c.ballMissing = true;
    }
}

class CollectAndControl : Tick
{
	mixin tick;

	override void run()
	{
        import std.conv;
        import flow.base.dev;

        auto c = this.entity.context.as!TrainerContext;
        c.counter = c.counter + 1;
        if(c.counter <= c.expectedKicks)
        {
            debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                ~ ") amount of kicks: " ~ c.counter.to!string, 1);

            if(c.counter == c.expectedKicks)
                this.send(new StopKicking);
        }
        else
        {
            debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                ~ ") sees " ~ this.trigger.source.id.toString
                ~ " still kicking and shouts 'I SAID STOP' ("~
                c.counter.to!string~")", 1);
        }
    }
}

class TakeBall : Tick
{
	mixin tick;

	override void run()
	{
        import flow.base.dev;
        
        auto c = this.entity.context.as!TrainerContext;
        debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
            ~ ") got ball back from " ~ this.trigger.source.id.toString, 1);
        
        c.ballMissing = false;
    }
}

class Trainer : Entity
{
    mixin entity!(TrainerContext);

    mixin listen!(fqn!(Whisper),
        (e, s) => new ListenToTheWhispering
    );

    mixin listen!(fqn!(BallKicked),
        (e, s) => new CollectAndControl
    );

    mixin listen!(fqn!(ReturnBall),
        (e, s) => new TakeBall
    );
}