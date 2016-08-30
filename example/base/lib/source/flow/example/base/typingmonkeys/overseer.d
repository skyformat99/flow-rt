module flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.signals;

import flow.blocks, flow.interfaces;

// just an internal signal, therefor located here
class FoundNotify : Unicast{mixin signal!(GermanPage);}

/** she needs to know a few things
and has a found flag */
class OverseerContext : Data
{
	mixin data;

    mixin field!(string, "search");
    mixin field!(ulong, "pages");
    mixin field!(bool, "found");
}

/** search the texts for the bible (parallel)
she's got the power' */
class Search : Tick
{
	mixin tick;

	override void run()
	{
        import std.algorithm, std.conv;
        import flow.dev;

        auto c = this.entity.context.as!OverseerContext;
        auto s = this.trigger.as!GermanText;

        // search
        if(canFind(s.data.text, c.search))
        {
            c.found = true;

            debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                ~ ") found \"" ~ c.search
                ~ "\" after searching "
                ~ c.pages.to!string ~ " pages and "
                ~ (c.pages*4).to!string
                ~ "kB of random bytes", 1);

                /* notifying herself that she found something
                you may now ask, why do this via signalling?
                by doing this via signalling its possible
                to override signal from a derrived overseer */
                auto found = new FoundNotify;
                found.data = s.data;
                this.send(found, this.entity);
        }

        c.pages = c.pages + 1;
    }
}

class Found : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!FoundNotify;
        /* she is a real sweetheart giving
        the successful monkey a candy */
        this.send(new Candy, s.data.author);
    }
}

Object handleFoundNotify(IEntity e, IFlowSignal s)
{
    return e.identWith(s.source) ? new Found : null;
}

/** and finally defining her
(black hair, deep green eyes) */
class Overseer : Entity
{
    mixin entity!(OverseerContext);
    
    mixin listen!(fqn!GermanText,
        (e, s) => e.context.as!OverseerContext.search !is null &&
            e.context.as!OverseerContext.search != "" ?
                new Search :
                null
    );
    
    mixin listen!(fqn!FoundNotify,
        (e, s) => handleFoundNotify(e, s)
    );
}