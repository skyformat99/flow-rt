module flow.example.base.madtypingmonkeys.madtypingmonkeys;
import flow.example.base.typingmonkeys.typingmonkeys;
import flow.example.base.typingmonkeys.signals;
import flow.example.base.typingmonkeys.overseer;
import flow.example.base.madtypingmonkeys.madmonkey;
import flow.example.base.typingmonkeys.translator;

import std.uuid;

import flow.blocks;

class MadTypingMonkeysConfig : TypingMonkeysConfig
{
	mixin data;
}
class MadTypingMonkeysContext : TypingMonkeysContext
{
	mixin data;

    mixin field!(bool, "candyHidden");
    mixin field!(ulong, "active");
}

class MadTypingMonkeys : Organ
{
    mixin organ!(MadTypingMonkeysConfig);

    override IData start()
    {
        auto c = config.as!TypingMonkeysConfig;
        auto d = new MadTypingMonkeysContext;

        // create and add the overseer
        auto overseer = new Overseer(c.domain);
        // we need her context later in this scope
        overseer.context.as!OverseerContext.search = c.search;
        d.overseer = this.process.add(overseer);

        // create and add a translator
        auto translator = new Translator(c.domain);
        d.translator = this.process.add(translator);
        auto am = c.amount;
        auto se = c.search;
        // create and add the monekeys
        // also their contexts we give
        // a local representation for late use
        for(auto i = 0; i < c.amount; i++)
        {
            auto monkey = new MadMonkey(c.domain);
            d.monkeys.put(this.process.add(monkey));
        }
            
        // bring god signal into game to activate the swarm
        this.process.send(new Whisper);

        return d;
    }

    override void stop()
    {
        auto d = context.as!TypingMonkeysContext;

        foreach(id; d.monkeys)
            this.process.remove(id);
        
        this.process.remove(d.translator);
        this.process.remove(d.overseer);
    }

    override @property bool finished()
    {
        import std.algorithm.iteration;

        auto tmp = this.context; 
        auto d = this.context.as!MadTypingMonkeysContext;
        auto c = this.process.get(d.overseer).context.as!OverseerContext;

        auto overseerFoundBible = c.found;
        auto didOneHideCandy = false;
        auto amountOfActive = d.monkeys.length;
        foreach(id; d.monkeys)
        {
            auto m = this.process.get(id);
            auto mc = m.context.as!MadMonkeyContext;

            if(!didOneHideCandy)
                didOneHideCandy = mc.candyHidden;

            if(mc.isKo)
            amountOfActive--;
        }
        
        d.candyHidden = didOneHideCandy;
        d.active = amountOfActive;

        return overseerFoundBible && (didOneHideCandy || amountOfActive < 2);
    }
}