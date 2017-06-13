module flow.example.base.typingmonkeys.typingmonkeys;
import flow.example.base.typingmonkeys.signals;
import flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.monkey;
import flow.example.base.typingmonkeys.translator;

import std.uuid;

import flow.base.blocks;

class TypingMonkeysConfig : Data
{
	mixin data;

    mixin field!(string, "domain");
    mixin field!(uint, "amount");
    mixin field!(string, "search");
}

class TypingMonkeysContext : Data
{
	mixin data;

    mixin list!(UUID, "monkeys");
    mixin field!(UUID, "translator");
    mixin field!(UUID, "overseer");
}

class TypingMonkeys : Organ
{
    mixin organ!(TypingMonkeysConfig);

    override IData start()
    {
        auto c = config.as!TypingMonkeysConfig;
        auto d = new TypingMonkeysContext;

        // create and add the overseer
        auto overseer = new Overseer(c.domain);
        // we need her context later in this scope
        overseer.context.as!OverseerContext.search = c.search;
        this.hull.add(overseer);
        d.overseer = overseer.id;

        // create and add a translator
        auto translator = new Translator(c.domain);
        this.hull.add(translator);
        d.translator = translator.id;

        // create and add the monekeys
        // also their contexts we give
        // a local representation for late use
        for(auto i = 0; i < c.amount; i++)
        {
            auto monkey = new Monkey(c.domain);
            this.hull.add(monkey);
            d.monkeys.put(monkey.id);
        }
            
        // bring god signal into game to activate the swarm
        this.hull.send(new Whisper);

        return d;
    }

    override void stop()
    {
        auto d = context.as!TypingMonkeysContext;

        foreach(id; d.monkeys)
            this.hull.remove(id);
        
        this.hull.remove(d.translator);
        this.hull.remove(d.overseer);
    }

    override @property bool finished()
    {
        import std.array;
        import std.algorithm.iteration;
        import std.algorithm.searching;
        auto d = context.as!TypingMonkeysContext;

        auto c = this.hull.get(d.overseer).context.as!OverseerContext;
        auto overseerFoundBible = c.found;
        auto allMonkeyStoppedTyping = d.monkeys.array.map!(m=>this.hull.get(m))
            .all!(m=>m.context.as!MonkeyContext.state != MonkeyEmotionalState.Calm);
                
        return overseerFoundBible && allMonkeyStoppedTyping;
    }
}