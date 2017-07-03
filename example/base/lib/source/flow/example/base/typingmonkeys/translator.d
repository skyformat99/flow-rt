module flow.example.base.typingmonkeys.translator;
import flow.example.base.typingmonkeys.signals;

import flow.base.blocks;

class TranslatorContext : Data {
	mixin data;

    mixin field!(ulong, "counter");
}

/** a function for better isolating the algorithm
in theory what happens here can be a covered
by a huge oop hierarchy.
but you may have to rethink
if you are using the right tool. */
string translate(byte[] arr) {
    auto str = "";
    foreach(b; arr)
        if(b >= 32 && b <= 126)
            str ~= b;

    return str;
}

/** well, translate using the translate algorithm
and multicast the translation */
class Translate : Tick {
	mixin tick;

	override void run() {
        import std.conv;
        import flow.base.dev;
        
        auto c = this.context.as!TranslatorContext;
        auto s = this.signal.as!HebrewText;

        auto gs = new GermanText;
        gs.data = new GermanPage;
        gs.data.text = s.data.text.translate();
        // not to forget the author
        gs.data.author = s.data.author;
        // multicast it
        this.send(gs);

        c.counter = c.counter + 1;

        this.msg(DL.Debug, "amount of translated pages: " ~ c.counter.to!string);
    }
}

/** and finally the translator itself
in the opposite to a monkey there is
one single tick executed in parallel */
class Translator : Entity {
    mixin entity;

    mixin listen!(fqn!HebrewText, fqn!Translate);
}