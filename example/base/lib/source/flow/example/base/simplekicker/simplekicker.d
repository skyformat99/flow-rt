module flow.example.base.simplekicker.simplekicker;
import flow.example.base.simplekicker.kicker;

import std.uuid;

import flow.blocks;

class SimpleKickerConfig : Data
{
	mixin data;

    mixin field!(string, "domain");
    mixin field!(uint, "amount");
    mixin field!(uint, "times");
}

class SimpleKickerContext : Data
{
	mixin data;

    mixin list!(UUID, "kicker");
}

class SimpleKicker : Organ
{
    mixin organ!(SimpleKickerConfig);

    override IData start()
    {
        auto c = config.as!SimpleKickerConfig;
        auto d = new SimpleKickerContext;

        // add kicker entities to the local swarm
        for(auto i = 0; i < c.amount; i++)
        {
            auto kicker = new Kicker(c.domain);
            kicker.context.as!KickerContext.times = c.times;
            this.hull.add(kicker);
            d.kicker.put(kicker.id);
        }

        // bring god signal into game to activate the swarm
        auto first = this.hull.get(d.kicker.front); 
        this.hull.send(new Ball, first);

        return d;
    }

    override void stop()
    {
        auto c = this.context.as!SimpleKickerContext;

        foreach(id; c.kicker)
            this.hull.remove(id);
    }

    override bool finished()
    {
        auto c = this.context.as!SimpleKickerContext;

        foreach(id; c.kicker)
            if(this.hull.get(id).context.as!KickerContext.done)
                return true;

        return false;
    }
}