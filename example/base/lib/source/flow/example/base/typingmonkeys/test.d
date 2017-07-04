module flow.example.base.typingmonkeys.test;
import flow.example.base.typingmonkeys.overseer;
import flow.example.base.typingmonkeys.translator;
import flow.example.base.typingmonkeys.monkey;

import flow.base.blocks, flow.base.data;

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
        mm.info.ptr.type = "flow.example.base.typingmonkeys.monkey.Monkey";
        mm.info.ptr.domain = domain;
        mm.context = new MonkeyContext;
        mm.context.as!MonkeyContext.state = MonkeyEmotionalState.Calm;

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
private bool waitForMonkeys(Flow f, EntityInfo i) {
    foreach(m; f.get(i).children) {
        auto c = m.meta.context.as!MonkeyContext;
        if(c !is null && c.state == MonkeyEmotionalState.Calm) {
            return false;
        }
    }

    return true;
}

/// finally we run that
void run(uint amount, string search) {
    import core.time;
    import std.datetime, std.conv, std.stdio, std.ascii;
    import flow.base.dev;

    Debug.msg(DL.Info, "#######################################");
    Debug.msg(DL.Info, "#######################################");
    Debug.msg(DL.Info, "### "~amount.to!string~" type writing monkeys, one translator");
    Debug.msg(DL.Info, "### and an overseer looking out for the bible");
    Debug.msg(DL.Info, "#######################################");

    // unimportant for example
    ulong pages;
    EntityMeta m;

    // unimportant for example
    auto f = {
        auto domain = "flow.example.typingmonkeys";

        // build flow config
        auto fc = new FlowConfig;
        fc.ptr = new FlowPtr;
        fc.tracing = false;
        fc.preventIdTheft = true;

        auto em = createMeta(domain, amount, search);

        // create a new flow hosting the local swarm
        auto flow = new Flow(fc);
        flow.add(em);

        // wait for an event indicating that swarm can be shut down
        flow.wait((){return waitForMonkeys(flow, em.info);});

        // shut down local swarm writing causal state to console
        m = flow.snap().front;

        flow.dispose();
    };

    
    auto b = benchmark!(f)(1);
    Debug.msg(DL.Info, "#######################################");
    Debug.msg(DL.Info, "time required for finding \"" ~ search ~ "\" "
        ~ "using " ~ amount.to!string ~ " monkeys "
        ~ "reviewed " ~ m.context.as!OverseerContext.pages.to!string ~ " pages "
        ~ "searched " ~ ((m.context.as!OverseerContext.pages*4)/1024).to!string ~ " MB of random data"
        ~ ": " ~ b[0].usecs.to!string
        ~ "usecs"~newline~m.json);
    Debug.msg(DL.Info, "#######################################");
}

/** two kicker playing ball and one trainer
watching and controlling the kicker */
unittest {
    run(5, "fo");
}