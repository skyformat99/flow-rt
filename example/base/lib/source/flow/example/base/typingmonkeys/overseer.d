module flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.signals;

import flow.base.blocks, flow.base.signals, flow.base.interfaces;

// just an internal signal, therefor located here
class FoundNotify : Unicast{mixin signal!(GermanPage);}

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
        if(cfg.search !is null && cfg.search != "" && canFind(s.data.text, cfg.search)) {
            c.found = true;

            debugMsg(this.entity.ptr.type~"|"~this.entity.ptr.id~"@"~this.entity.ptr.domain
                ~" found \""~cfg.search
                ~"\" after searching "
                ~c.pages.to!string~" pages and "
                ~(c.pages*4).to!string
                ~"kB of random bytes", 1);

                /* notifying herself that she found something
                you may now ask, why do this via signalling?
                by doing this via signalling its possible
                to override signal from a derrived overseer */
                auto found = new FoundNotify;
                found.data = s.data;
                this.send(found, this.entity.ptr);
        }

        c.pages = c.pages + 1;
    }
}

class Found : Tick {
	mixin tick;

	override void run() {
        if(this.signal.source.identWith(this.entity.ptr)) {
            auto s = this.signal.as!FoundNotify;
            /* she is a real sweetheart giving
            the successful monkey a candy */
            this.send(new Candy, s.data.author);
        }
    }
}

/** and finally defining her
(black hair, deep green eyes) */
class Overseer : Entity {
    mixin entity!(OverseerContext);
    
    mixin listen!(fqn!GermanText, fqn!Search);    
    mixin listen!(fqn!FoundNotify, fqn!Found);
}