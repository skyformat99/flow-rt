module flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.signals;

import flow.base.blocks, flow.base.signals, flow.base.interfaces;

/// she needs to know a few things
class OverseerConfig : Data {
	mixin data;
    
    mixin field!(string, "search");
}

/// she needs to remember a few things
class OverseerContext : Data {
	mixin data;

    mixin field!(ulong, "pages");
    mixin field!(bool, "found");
}

/** search the texts for the bible (parallel)
she's got the power' */
class Search : Tick {
	mixin tick;

	override void run() {
        import std.algorithm, std.conv;
        import flow.base.dev;

        auto cfg = this.entity.config.as!OverseerConfig;
        auto c = this.context.as!OverseerContext;
        auto s = this.signal.as!GermanText;

        // search
        if(!c.found && cfg.search !is null && cfg.search != "" && canFind(s.data.text, cfg.search))
            this.next(fqn!Found);

        c.pages = c.pages + 1;
    }
}

class Found : Tick {
    mixin sync;

    override void run() {
        import std.algorithm, std.conv;
        import flow.base.dev;

        auto cfg = this.entity.config.as!OverseerConfig;
        auto c = this.context.as!OverseerContext;
        auto s = this.signal.as!GermanText;

        c.found = true;

        this.msg(DL.Debug, "found \""~cfg.search
            ~"\" after searching "
            ~c.pages.to!string~" pages and "
            ~(c.pages*4).to!string
            ~"kB of random bytes");
            
            /* she is a real sweetheart giving
            the successful monkey a candy */
            this.send(new Candy, s.data.author);
    }
}

/** and finally defining her
(black hair, deep green eyes) */
class Overseer : Entity {
    mixin entity;
    
    mixin listen!(fqn!GermanText, fqn!Search);
}