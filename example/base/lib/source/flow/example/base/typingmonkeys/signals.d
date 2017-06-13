module flow.example.base.typingmonkeys.signals;
/* module gives everything in this file a namespace
it has to be in the first line */

// some imports
import flow.base.blocks, flow.base.data;

// for monkey
/** a so called god signal,
sent directly from the one controlling the swarm.
this one is meant to trigger the swarm at startup
by whispering "type" to the monkeys. */
class Whisper : Multicast{mixin signal!();}

/** the monkey gets a candy from overseer if it types the bible */
class Candy : Unicast{mixin signal!();}

/** no, the monkey is not discrete
it shows to all other monkeys what it won */
class ShowCandy : Multicast{mixin signal!();}

// for translator
/** well, the original bible is in hebrew
the monkeys are typing on hebrew type writers
* EntityRef is a reference to an entity
* entity refs are never matched e == e but always e.identWith(e) */
class HebrewPage : Data
{
	mixin data;

    mixin field!(byte[], "text");
    mixin field!(EntityRef, "author");
}
/** the data belongs to a multicast
* the data carrying field: data */
class HebrewText : Multicast{mixin signal!(HebrewPage);}

// for oversser
/** the overseer is a german,
so there has to be a translation to deliver */
class GermanPage : Data
{
	mixin data;

    mixin field!(string, "text");
    mixin field!(EntityRef, "author");
}
/** which belongs to a signal */
class GermanText : Multicast{mixin signal!(GermanPage);}