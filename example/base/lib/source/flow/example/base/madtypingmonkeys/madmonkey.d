module flow.example.base.madtypingmonkeys.madmonkey;
import flow.example.base.typingmonkeys.signals;
import flow.example.base.typingmonkeys.monkey;

import flow.base.blocks, flow.base.data, flow.base.interfaces;

class Punch : Unicast{mixin signal!();}
class KoInfo : Data
{
	mixin data;

    mixin field!(EntityPtr, "raider");
}
class NotifyKo : Multicast{mixin signal!(KoInfo);}
class NotifyNoKo : Unicast{mixin signal!();}

class DropCandy : Anycast{mixin signal!();}

int koAt = -100;
class MadMonkeyContext : MonkeyContext
{
	mixin data;

    mixin field!(int, "health");
    mixin field!(bool, "isKo");
    mixin field!(bool, "candyHidden");
}

class GoMad : Tick
{
	mixin tick;

	override void run()
	{
        import flow.base.dev;

        auto s = this.trigger;
        auto c = this.entity.context.as!MadMonkeyContext;

        c.state = MonkeyEmotionalState.Dissapointed;
            
        auto sent = this.answer(new Punch);
        // just something for us to see
        debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
            ~ ") got dissapointed and "~(sent ? "successfully" : "unsuccessfully")~" punches "
            ~ s.source.type ~ " (" ~ s.source.id.toString ~ ")", 1);
    }
}

class Punched : Tick
{
	mixin tick;

	override void run()
	{
        import std.random;
        import flow.base.dev;

        auto s = this.trigger.as!Punch;
        auto c = this.entity.context.as!MadMonkeyContext;

        if(c.isKo)
        {
            auto sent = this.send(new DropCandy);
            // just something for us to see
            debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                ~ ") was koed by "
                ~ s.source.type ~ " (" ~ s.source.id.toString ~ ")"
                ~ " and "~(sent ? "successfully" : "unsuccessfully")~" drops candy", 1);

            this.send(new NotifyKo);
        }
        else
        {         
            if(uniform(0, 1) == 0)
            {
                auto sent2 = this.answer(new Punch);
                // just something for us to see
                debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                    ~ ") "~(sent2 ? "successfully" : "unsuccessfully")~" punches back at "
                    ~ s.source.type ~ " (" ~ s.source.id.toString ~ ")", 1);
            }

            auto sent = this.send(new NotifyNoKo, s.source);
            debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                ~ ") "~(sent ? "successfully" : "unsuccessfully")~" notifies "
                ~ s.source.type ~ " (" ~ s.source.id.toString ~ ") that it isn't KO'", 1);
        }
    }
}

class CatchCandy : Tick
{
	mixin tick;

	override void run()
	{
        import std.random;
        import flow.base.dev;

        auto c = this.entity.context.as!MadMonkeyContext;
        
        if(!c.isKo) // it may happen
        {
            c.state = MonkeyEmotionalState.Happy;
            c.candyHidden = uniform(0, 50) == 0; // 1/50 chance to hide

            // is it hiding or showing it?
            if(c.candyHidden)
            {
                // just something for us to see
                debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                    ~ ") catched dropped candy and hides it", 1);
            }
            else
            {
                // just something for us to see
                debugMsg(fqnOf(this.entity) ~ " (" ~ this.entity.id.toString
                    ~ ") catched dropped candy and shows it", 1);

                this.send(new ShowCandy);
            }
        }
        else this.send(new DropCandy);
    }
}

private Object onPunch(Entity e, Signal signal)
{
    import std.conv, std.random;
    import flow.base.dev;
    
    auto s = signal.as!Punch;
    auto c = e.context.as!MadMonkeyContext;

    if(!s.source.identWith(e) && !c.isKo)
    {                
        auto hit = uniform(0, 1) == 0;
                
        // estimate if that was a hit
        if(hit)
        {
            c.health = c.health - 10;
            c.isKo = c.health <= koAt;
                        
            // just something for us to see
            debugMsg(fqnOf(e) ~ " (" ~ e.id.toString
                ~ ") got punched(left health "
                ~ (c.health-koAt).to!string ~ ") and is "~(!c.isKo ? "not " : "")~"KO by "
                ~ s.source.type ~ " (" ~ s.source.id.toString ~ ")", 1);
        }
        return new Punched;
    } else return null;
}

Object handleShowCandy(Entity e, Signal s)
{
    return !s.source.identWith(e) &&
        !e.context.as!MadMonkeyContext.isKo
        ? new GoMad : null;
}

Object handleNotifyNoKo(Entity e, Signal s)
{
    return !s.source.identWith(e) &&
        !e.context.as!MadMonkeyContext.isKo ?
        new GoMad : null;
}

Object handleDropCandy(Entity e, Signal s)
{
    return !s.source.identWith(e) &&
        !e.context.as!MadMonkeyContext.isKo ?
        new CatchCandy : null;
}

class MadMonkey : Monkey
{
    mixin entity!(MadMonkeyContext);

    mixin listen!(fqn!ShowCandy,
        (e, s) => handleShowCandy(e, s)        
    );
    
    mixin listen!(fqn!NotifyNoKo,
        (e, s) => handleNotifyNoKo(e, s)
    );

    mixin listen!(fqn!Punch,
        (e, s) => onPunch(e, s)
    );

    mixin listen!(fqn!DropCandy,
        (e, s) => handleDropCandy(e, s)
    );
}