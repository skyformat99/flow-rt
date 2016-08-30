module flow.example.base.trainingkicker.trainingkicker;
import flow.example.base.trainingkicker.signals;
import flow.example.base.trainingkicker.trainer;
import flow.example.base.trainingkicker.trainedkicker;
import flow.example.base.simplekicker.kicker;

import std.uuid;

import flow.blocks;

class TrainingKickerConfig : Data
{
	mixin data;

    mixin field!(string, "domain");
    mixin field!(uint, "amount");
    mixin field!(uint, "times");
}

class TrainingKickerContext : Data
{
	mixin data;

    mixin field!(UUID, "trainer");
    mixin list!(UUID, "kicker");
}

class TrainingKicker : Organ
{
    mixin organ!(TrainingKickerConfig);

    override IData start()
    {
        auto c = config.as!TrainingKickerConfig;
        auto d = new TrainingKickerContext;

        auto trainer = new Trainer(c.domain);
        trainer.context.as!TrainerContext.expectedKicks = c.times;
        this.process.add(trainer);
        d.trainer = trainer.id;

        // add kicker entities to the local swarm
        for(auto i = 0; i < c.amount; i++)
        {
            auto kicker = new TrainedKicker(c.domain);
            kicker.context.as!KickerContext.times = c.times;
            this.process.add(kicker);
            d.kicker.put(kicker.id);
        }

        // bring god signal into game to activate the swarm
        auto s = new Whisper;
        s.data = this.process.get(d.kicker.front).info.reference;
        this.process.send(s, trainer);

        return d;
    }

    override void stop()
    {
        auto c = this.context.as!TrainingKickerContext;

        foreach(id; c.kicker)
            this.process.remove(id);
        
        this.process.remove(c.trainer);
    }

    override @property bool finished()
    {
        auto d = this.context.as!TrainingKickerContext;
        auto c = this.process.get(d.trainer).context.as!TrainerContext;
        return c.counter >= c.expectedKicks && !c.ballMissing;
    } 
}