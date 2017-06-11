module flow.example.base.madtypingmonkeys.test;
import flow.example.base.typingmonkeys.typingmonkeys;
import flow.example.base.madtypingmonkeys.madtypingmonkeys; // no we do not require it, but we need the data registrations
import flow.example.base.typingmonkeys.overseer;

/// finally we run that
void run(uint amount, string search)
{
    import core.time;
    import std.datetime, std.conv;
    import flow.dev, flow.blocks;

    debugMsg("#######################################", 0);
    debugMsg("#######################################", 0);
    debugMsg("### "~amount.to!string~" type writing monkeys, one translator", 0);
    debugMsg("### and an overseer looking out for the bible", 0);
    debugMsg("#######################################", 0);

    // unimportant for example
    ulong pages;
    bool didOneHideCandy;
    ulong amountOfActive;
    
    // unimportant for example
    auto f =
    {
        // build organ configuration using json
        auto configStr = "{
            \"dataType\": \"flow.example.base.madtypingmonkeys.madtypingmonkeys.MadTypingMonkeysConfig\",
            \"amount\": "~amount.to!string~",
            \"search\": \""~search~"\",
            \"domain\": \"example.madtypingmonkeys\"
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

        auto od = organ.context.as!MadTypingMonkeysContext;
        didOneHideCandy = od.candyHidden;
        amountOfActive = od.active;

        // shut down local swarm
        flow.stop();
    };
    
    auto b = benchmark!(f)(1);
    debugMsg("time required for finding \"" ~ search ~ "\" "
        ~ "using " ~ amount.to!string ~ " monkeys "
        ~ "reviewed " ~ pages.to!string ~ " pages "
        ~ "searched " ~ ((pages*4)/1024).to!string ~ " MB of random data "
        ~ "the candy is " ~ (didOneHideCandy ? "hidden " : "not hidden ")
        ~ "and " ~ amountOfActive.to!string ~ " monkeys are left "
        ~ ": " ~ b[0].usecs.to!string
        ~ "usecs", 0);
    debugMsg("#######################################", 0);
    debugMsg("", 0);
}

/** two kicker playing ball and one trainer
watching and controlling the kicker */
unittest
{
    run(10, "fo");
}