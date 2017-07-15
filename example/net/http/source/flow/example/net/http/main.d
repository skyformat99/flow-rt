module flow.example.net.http.main;

import core.thread;
import core.time;
import std.stdio, std.file, std.path, std.uuid;
import flow.base.blocks, flow.base.data, flow.base.interfaces;
import flow.base.dev;
import flow.net.beacon, flow.net.http;

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
class OverseerGiveCandy : Unicast{mixin signal!(EntityPtr);}

class NotifyThatFound : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.signal.as!FoundNotify;
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
        auto s = this.signal.as!OverseerGiveCandy;
        this.send(new Candy, s.data);
    }
}

class Search : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.signal.as!OverseerSearch;
        auto c = this.context.as!OverseerContext;
        c.search = s.data.search;
        this.send(new Whisper);
    }
}

Object handleFoundNotify(Entity e, Signal s)
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

    override Data start()
    {
        auto d = new CommTypingMonkeysContext;
        auto c = config.as!CommTypingMonkeysConfig;

        // create and add the overseer
        d.overseer = this.hull.add(new CommunicatingOverseer);

        // create and add a translator
        d.translator = this.hull.add(new Translator);

        // create and add the monekeys
        // also their contexts we give
        // a local representation for late use
        Monkey[] monkeys;
        for(auto i = 0; i < c.amount; i++)
        {
            auto m = c.useMad ? new MadMonkey : new Monkey;
            monkeys ~= m;
            d.monkeys.put(this.hull.add(m));
        }

        return d;
    }

    override void stop()
    {
        auto d = context.as!CommTypingMonkeysContext;

        foreach(m; d.monkeys)
            this.hull.remove(m);
        
        this.hull.remove(d.translator);
        this.hull.remove(d.overseer);
    }
}

version(posix) import core.sys.posix.signal;

bool stopped = false;

void stop()
{
    stopped = true;
}

void main(string[] args)
{
    import std.conv;

    version(posix) sigset(SIGINT, &stop);

    auto port = args.length > 2 ? args[1].to!ushort : 1234;
    auto amount = 3;
    auto useMad = false;

    // build web organ configuration using json
    auto wcStr = "{
        \"dataType\": \"flow.net.http.HttpConfig\",
        \"port\": "~port.to!string~",
        \"listenerAmount\": 10,
        \"root\": \""~thisExePath.dirName.buildPath("public")~"\",
        \"domain\": \"example.net.http\"
    }";
    auto wc = Data.fromJson(wcStr);

    // build comm typing monkeys organ configuration using json
    auto mcStr = "{
        \"dataType\": \"flow.example.net.http.main.CommTypingMonkeysConfig\",
        \"amount\": "~amount.to!string~",
        \"useMad\": "~useMad.to!string~",
        \"domain\": \"example.net.http\"
    }";
    auto mc = Data.fromJson(mcStr);
    
    auto fc = new FlowConfig;
    fc.workers = threadsPerCPU()/2;
    fc.tracing = true;
    fc.preventIdTheft = false;
    
    // create a new process hosting the local swarm
    auto flow = new Flow(fc);

    // add web organ
    auto wo = Organ.create(wc);
    flow.add(wo);

    // add comm typing monkeys organ
    auto mo = Organ.create(mc);
    flow.add(mo);

    //flow.wait();
    while(!stopped)
        Thread.sleep(dur!("msecs")(100));

    // shut down local swarm
    flow.stop();
}