module flow.example.util.web.main;

import core.thread;
import core.time;
import std.stdio, std.file, std.path, std.uuid;
import flow.blocks, flow.data, flow.interfaces;
import flow.dev;
import flow.util.web;

import flow.example.base.typingmonkeys.signals;
import flow.example.base.typingmonkeys.monkey;
import flow.example.base.madtypingmonkeys.madmonkey;
import flow.example.base.typingmonkeys.translator;
import flow.example.base.typingmonkeys.overseer;

class OverseerSearchData : Data
{
	mixin data;

    mixin field!(string, "search");
}
class OverseerSearch : Unicast{mixin signal!(OverseerSearchData);}
class OverseerFound : Multicast{mixin signal!(GermanPage);}
class OverseerGiveCandy : Unicast{mixin signal!(EntityRef);}

class NotifyThatFound : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!FoundNotify;
        auto found = new OverseerFound;
        found.data = s.data;
        this.send(found);
    }
}

class GiveCandy : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!OverseerGiveCandy;
        this.send(new Candy, s.data);
    }
}

class Search : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!OverseerSearch;
        auto c = this.entity.context.as!OverseerContext;
        c.search = s.data.search;
        this.send(new Whisper);
    }
}

Object handleFoundNotify(IEntity e, ISignal s)
{
    return e.identWith(s.source) ? new NotifyThatFound : null;
}

class CommunicatingOverseer : Overseer
{
    mixin entity!(OverseerContext);

    mixin listen!(fqn!OverseerSearch,
        (e, s) => s.as!OverseerSearch.data !is null ? new Search : null
    );

    mixin listen!(fqn!FoundNotify,
        (e, s) => handleFoundNotify(e, s)
    );

    mixin listen!(fqn!OverseerGiveCandy,
        (e, s) => new GiveCandy
    );
}

class CommTypingMonkeysConfig : Data
{
	mixin data;

    mixin field!(uint, "amount");
    mixin field!(bool, "useMad");
    mixin field!(string, "domain");
}

class CommTypingMonkeysContext : Data
{
	mixin data;

    mixin list!(UUID, "monkeys");
    mixin field!(UUID, "overseer");
    mixin field!(UUID, "translator");
}

class CommTypingMonkeys : Organ
{
    mixin organ!(CommTypingMonkeysConfig);

    override IData start()
    {
        auto d = new CommTypingMonkeysContext;
        auto c = config.as!CommTypingMonkeysConfig;

        // create and add the overseer
        d.overseer = this.process.add(new CommunicatingOverseer);

        // create and add a translator
        d.translator = this.process.add(new Translator);

        // create and add the monekeys
        // also their contexts we give
        // a local representation for late use
        Monkey[] monkeys;
        for(auto i = 0; i < c.amount; i++)
        {
            auto m = c.useMad ? new MadMonkey : new Monkey;
            monkeys ~= m;
            d.monkeys.put(this.process.add(m));
        }

        return d;
    }

    override void stop()
    {
        auto d = context.as!CommTypingMonkeysContext;

        foreach(m; d.monkeys)
            this.process.remove(m);
        
        this.process.remove(d.translator);
        this.process.remove(d.overseer);
    }
}

void main(string[] args)
{
    import std.conv;

    auto port = args.length > 2 ? args[1].to!ushort : 1234;
    auto amount = 3;
    auto useMad = false;

    // build web organ configuration using json
    auto wcStr = "{
        \"dataType\": \"flow.util.web.WebConfig\",
        \"port\": "~port.to!string~",
        \"listenerAmount\": 10,
        \"root\": \""~thisExePath.dirName.buildPath("public")~"\",
        \"domain\": \"example.web\"
    }";
    auto wc = Data.fromJson(wcStr);

    // build comm typing monkeys organ configuration using json
    auto mcStr = "{
        \"dataType\": \"flow.example.util.web.main.CommTypingMonkeysConfig\",
        \"amount\": "~amount.to!string~",
        \"useMad\": "~useMad.to!string~",
        \"domain\": \"example.web\"
    }";
    auto mc = Data.fromJson(mcStr);

    // create a new process hosting the local swarm
    auto process = new Process;
    process.tracing = true;

    // add web organ
    auto wo = Organ.create(wc);
    process.add(wo);

    // add comm typing monkeys organ
    auto mo = Organ.create(mc);
    process.add(mo);

    process.wait();

    // shut down local swarm
    process.stop();
}