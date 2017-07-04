module flow.example.base.madtypingmonkeys.madmonkey;
import flow.example.base.typingmonkeys.signals;
import flow.example.base.typingmonkeys.monkey;

import flow.base.blocks, flow.base.data, flow.base.signals, flow.base.interfaces;

class Punch : Unicast{mixin signal!();}
class KoInfo : Data {
	mixin data;

    mixin field!(EntityPtr, "raider");
}
class NotifyKo : Multicast{mixin signal!(KoInfo);}
class NotifyNoKo : Unicast{mixin signal!();}

class DropCandy : Anycast{mixin signal!();}

class MadMonkeyConfig : Data {
	mixin data;

    mixin field!(int, "koAt");
}

class MadMonkeyContext : MonkeyContext {
	mixin data;

    mixin field!(int, "health");
    mixin field!(bool, "isKo");
    mixin field!(bool, "candyHidden");
}

class GoMad : Tick {
	mixin tick;

	override void run() {
        import flow.base.dev;

        auto s = this.signal;
        auto c = this.context.as!MadMonkeyContext;

        if(!s.source.identWith(this.entity.ptr) && !c.isKo) {
            c.state = MonkeyEmotionalState.Dissapointed;
                
            auto sent = this.answer(new Punch);
            // just something for us to see
            this.msg(DL.Debug, "got dissapointed and "~(sent ? "successfully" : "unsuccessfully")~" punches "
                ~s.source.type~"("~s.source.id~")");
        }
    }
}

class TakePunch : Tick {
    mixin tick;

    override void run() {
        import std.conv, std.random;
        import flow.base.dev;
        
        auto s = this.signal.as!Punch;
        auto cfg = this.entity.config.as!MadMonkeyConfig;
        auto c = this.context.as!MadMonkeyContext;

        if(!s.source.identWith(this.entity.ptr) && !c.isKo) {                
            auto hit = uniform(0, 1) == 0;
                    
            // estimate if that was a hit
            if(hit) {
                c.health = c.health - 10;
                c.isKo = c.health <= cfg.koAt;
                            
                // just something for us to see
                this.msg(DL.Debug, "got punched(left health "
                    ~(c.health-cfg.koAt).to!string ~ ") and is "~(!c.isKo ? "not " : "")~"KO by "
                    ~s.source.type~" ("~s.source.id~")");
            }

            this.next(fqn!Punched);
        }
    }
}

class Punched : Tick {
	mixin tick;

	override void run() {
        import std.random;
        import flow.base.dev;

        auto s = this.signal.as!Punch;
        auto c = this.context.as!MadMonkeyContext;

        if(c.isKo) {
            auto sent = this.send(new DropCandy);
            // just something for us to see
            this.msg(DL.Debug, s.source, "was koed and "
                ~(sent ? "successfully" : "unsuccessfully")~" drops candy");

            this.send(new NotifyKo);
        }
        else {         
            if(uniform(0, 1) == 0) {
                auto sent2 = this.answer(new Punch);
                // just something for us to see
                this.msg(DL.Debug, s.source, (sent2 ? "successfully" : "unsuccessfully")~" punches back"
                    ~ s.source.type);
            }

            auto sent = this.send(new NotifyNoKo, s.source);
            this.msg(DL.Debug, s, (sent ? "successfully" : "unsuccessfully")
                ~" notifies that it isn't KO'");
        }
    }
}

class CatchCandy : Tick {
	mixin tick;

	override void run() {
        import std.random;
        import flow.base.dev;

        auto s = this.signal.as!DropCandy;
        auto c = this.context.as!MadMonkeyContext;
        
        c.state = MonkeyEmotionalState.Happy;
        c.candyHidden = uniform(0, 50) == 0; // 1/50 chance to hide

        // is it hiding or showing it?
        if(c.candyHidden) {
            // just something for us to see
            this.msg(DL.Debug, "catched dropped candy and hides it");
        }
        else {
            // just something for us to see
            this.msg(DL.Debug, "catched dropped candy and shows it");

            this.send(new ShowCandy);
        }
    }
}

class MadMonkey : Monkey {
    mixin entity;

    mixin listen!(fqn!ShowCandy, fqn!GoMad);    
    mixin listen!(fqn!NotifyNoKo, fqn!GoMad);
    mixin listen!(fqn!Punch, fqn!TakePunch);
    mixin listen!(fqn!DropCandy, fqn!CatchCandy);

    override bool accept(Signal s) {
        // an ko monkey can't accept anything but usually you will use a switch
        return !this.context.as!MadMonkeyContext.isKo;
    }
}