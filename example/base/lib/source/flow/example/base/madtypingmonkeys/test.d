module flow.example.base.madtypingmonkeys.test;
import flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.translator;
import flow.example.base.typingmonkeys.monkey;
import flow.example.base.madtypingmonkeys.madmonkey;

import flow.base.blocks, flow.base.data, flow.base.dev;

/// we construct an initial causal snap for the system
private EntityMeta createMeta(string domain, uint amount, string search) {
    import std.conv;

    // build overseer meta
    auto om = new EntityMeta;
    om.info = new EntityInfo;
    om.info.ptr = new EntityPtr;
    om.info.ptr.id = "overseer";
    om.info.ptr.type = "flow.example.base.typingmonkeys.overseer.Overseer";
    om.info.ptr.domain = domain;
    auto oc = new OverseerConfig;
    oc.search = search;
    om.info.config = oc;
    om.context = new OverseerContext;

    // add translator child to overseer
    auto tm = new EntityMeta;
    tm.info = new EntityInfo;
    tm.info.ptr = new EntityPtr;
    tm.info.ptr.id = "translator";
    tm.info.ptr.type = "flow.example.base.typingmonkeys.translator.Translator";
    tm.info.ptr.domain = domain;
    tm.context = new TranslatorContext;

    om.children.put(tm);

    // add monkeys as childs to overseer
    for(uint i = 0; i < amount; i++) {
        auto mm = new EntityMeta;
        mm.info = new EntityInfo;
        mm.info.ptr = new EntityPtr;
        mm.info.ptr.id = "monkey_"~i.to!string;
        mm.info.ptr.type = "flow.example.base.madtypingmonkeys.madmonkey.MadMonkey";
        mm.info.ptr.domain = domain;
        auto mc = new MadMonkeyConfig;
        mc.koAt = -100;
        mm.info.config = mc;
        mm.context = new MadMonkeyContext;

        // in this constructed causality snap its about to execute write tick
        auto t = new TickMeta;
        t.info = new TickInfo;
        t.info.type = "flow.example.base.typingmonkeys.monkey.Write";

        mm.ticks.put(t);

        om.children.put(mm);
    }

    return om;
}

/// waiter for process to wait for an event before exiting
private bool waitForMonkeys(uint amount, Flow f, EntityInfo i) {
    auto koCount = 0;
    foreach(e; f.get(i).children) {
        auto c = e.context.as!MadMonkeyContext;
        if(c !is null) {
            if(c.state == MonkeyEmotionalState.Calm)
                return false;

            if(c.candyHidden)
                return true;

            if(c.isKo)
                koCount++;
        }
    }

    return koCount >= amount-1;
}

/// finally we run that
void run(uint amount, string search) {
    import core.cpuid, core.time;
    import std.datetime, std.conv, std.math;
    import flow.base.dev;

    // limiting the flow to half of the vcores
    //auto vcores = threadsPerCPU();
    //auto cpusetp = cast(cpu_set_t)(pow(2, vcores/2)-1);
    //sched_setaffinity(0, cpusetp.sizeof, &cpusetp);

    Log.msg(LL.Message, "#######################################");
    Log.msg(LL.Message, "#######################################");
    Log.msg(LL.Message, "### "~amount.to!string~" type writing monkeys, one translator");
    Log.msg(LL.Message, "### and an overseer looking out for the bible");
    Log.msg(LL.Message, "#######################################");
    

    // build flow config
    auto fc = new FlowConfig;
    fc.ptr = new FlowPtr;
    fc.tracing = false;
    fc.preventIdTheft = true;
    auto p = new Flow(fc);

    auto domain = "flow.example.madtypingmonkeys";
    auto em = createMeta(domain, amount, search);

    auto f = {
        // create a new flow hosting the local swarm
        p.add(em);

        // wait for an event indicating that swarm can be shut down
        p.wait((){return waitForMonkeys(amount, p, em.info);});
    };

    auto b = benchmark!(f)(1);

    // shut down local swarm writing causal state to console
    auto m = p.snap().front;

    p.dispose();

    auto candyHidden = false;
    auto koCount = 0;
    foreach(em; m.children) {
        auto c = em.context.as!MadMonkeyContext;
        if(c !is null) {
            if(c.candyHidden)
                candyHidden = true;

            if(c.isKo) koCount++;
        }
    }

    Log.msg(LL.Message, "#######################################");
    Log.msg(LL.Message, "time required for finding \"" ~ search ~ "\" "
        ~ "using " ~ amount.to!string ~ " monkeys "
        ~ "reviewed " ~ m.context.as!OverseerContext.pages.to!string ~ " pages "
        ~ "searched " ~ ((m.context.as!OverseerContext.pages*4)/1024).to!string ~ " MB of random data "
        ~ "the candy is " ~ (candyHidden ? "hidden " : "not hidden ")
        ~ "and " ~ (amount-koCount).to!string ~ " monkeys are left "
        ~ ": " ~ b[0].usecs.to!string
        ~ "usecs"~Debug.sep~m.json);
    Log.msg(LL.Message, "#######################################");
}

/** two kicker playing ball and one trainer
watching and controlling the kicker */
unittest
{
    run(10, "fo");
}