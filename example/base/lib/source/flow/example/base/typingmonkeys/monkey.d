module flow.example.base.typingmonkeys.monkey;
import flow.example.base.typingmonkeys.signals;

import flow.base.blocks, flow.base.data;

enum MonkeyEmotionalState {
    Calm,
    Happy,
    Dissapointed
}

/** ticks inside an entity can interact with each other
using a context the entity provides.
* basically its the memory of the entity.
* you can implement anything derriving from Object,
but you should stay with a data objects in most cases
* The monkey needs to know just two things
one for measuring its performance for us
and one to know how it feels */
class MonkeyContext : Data {
	mixin data;

    mixin field!(ulong, "counter");
    mixin field!(MonkeyEmotionalState, "state");
}


// what can the monkey do and how?
/** it should type
a tick has a [name] and defines an [algorithm].
the algorithm takes an [entity],
a [ticker] to control the internal flow */
class Write : Tick {
    mixin tick;

    override void run() {
        /* some imports necessary
        for the d and phobos functionality used */
        import std.random, std.conv;
        import flow.base.dev;

        /* sadly at the moment the context has
        to be casted to its type or interface */
        auto c = this.context.as!MonkeyContext;

        /* when the monkey gets happy it is distracted
        and when dissapointed it is restive
        so it only types when its calm */
        if(c.state == MonkeyEmotionalState.Calm) {
            byte[] arr;

            // get 4kb data from urandom
            for(auto i = 0; i < 1024*4; i++)
                arr ~= uniform(0, 255).as!byte;
            
            // create multicast
            auto s = new HebrewText;
            s.data = new HebrewPage;
            s.data.text = arr;
            s.data.author = this.entity.ptr;
            // send multicast
            this.send(s);

            // note the new page (++ sadly is not working yet)
            c.counter = c.counter + 1;

            // just something for us to see
            debugMsg(this.entity.ptr.type~"|"~this.entity.ptr.id~"@"~this.entity.ptr.domain
                ~" amount of typed pages: "~c.counter.to!string, 1);
            
            // tell the ticker to repeat this tick (natural while loop)
            this.repeat();
        }
    }
}

/** this one is pretty simple */
class GetCandy : Tick {
	mixin tick;

	override void run() {
        import flow.base.dev;

        auto c = this.context.as!MonkeyContext;

        c.state = MonkeyEmotionalState.Happy;

        this.send(new ShowCandy);

        // just something for us to see
        debugMsg(this.entity.ptr.type~"|"~this.entity.ptr.id~"@"~this.entity.ptr.domain
            ~" got happy", 1);
    }
}

/** this one too */
class SeeCandy : Tick {
	mixin tick;

	override void run() {
        import flow.base.dev;

        if(!this.signal.source.identWith(this.entity.ptr)) {
            auto c = this.context.as!MonkeyContext;

            c.state = MonkeyEmotionalState.Dissapointed;

            // just something for us to see
            debugMsg(this.entity.ptr.type~"|"~this.entity.ptr.id~"@"~this.entity.ptr.domain
                ~" got dissapointed", 1);
        }
    }
}

/** finally we define what a monkey is.
what it listens to and how it reacts
* so there is one main sequential tick string
* and two just setting something */
class Monkey : Entity {
    mixin entity!(MonkeyContext);

    mixin listen!(
        // type id of a candy
        fqn!Candy,
        // it gets happy
        fqn!GetCandy
    );

    mixin listen!(
        // type of "any monkey shows it candy"
        fqn!ShowCandy,
        // if it is not seeing the own candy it gets dissapointed
        fqn!SeeCandy
    );
}
