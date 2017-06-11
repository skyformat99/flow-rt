module flow.example.base.typingmonkeys.test;
import flow.example.base.typingmonkeys.typingmonkeys;
import flow.example.base.typingmonkeys.overseer;

import flow.blocks;

/// finally we run that
void run(uint amount, string search)
{
    import core.time;
    import std.datetime, std.conv;
    import flow.dev;

    debugMsg("#######################################", 0);
    debugMsg("#######################################", 0);
    debugMsg("### "~amount.to!string~" type writing monkeys, one translator", 0);
    debugMsg("### and an overseer looking out for the bible", 0);
    debugMsg("#######################################", 0);

    // unimportant for example
    ulong pages;
    
    // unimportant for example
    auto f =
    {
        // build organ configuration using json
        auto configStr = "{
            \"dataType\": \"flow.example.base.typingmonkeys.typingmonkeys.TypingMonkeysConfig\",
            \"amount\": "~amount.to!string~",
            \"search\": \""~search~"\",
            \"domain\": \"example.typingmonkeys\"
        }";
        auto config = Data.fromJson(configStr);

        // create a new flow hosting the local swarm
        auto flow = new Flow;

        // add typing monkeys organ
        auto organ = Organ.create(config);
        flow.add(organ);

        // wait for an event indicating that swarm can be shut down
        flow.wait();

        // unimportant for example
        auto overseer = flow.get(
            organ.context.as!TypingMonkeysContext.overseer);
        pages = overseer.context.as!OverseerContext.pages;

        // shut down local swarm
        flow.stop();
    };

    
    auto b = benchmark!(f)(1);
    debugMsg("time required for finding \"" ~ search ~ "\" "
        ~ "using " ~ amount.to!string ~ " monkeys "
        ~ "reviewed " ~ pages.to!string ~ " pages "
        ~ "searched " ~ ((pages*4)/1024).to!string ~ " MB of random data"
        ~ ": " ~ b[0].usecs.to!string
        ~ "usecs", 0);
    debugMsg("#######################################", 0);
    debugMsg("", 0);
}

/** two kicker playing ball and one trainer
watching and controlling the kicker */
unittest
{
    run(5, "fo");
}