module flow.example.base.simplekicker.test;
import flow.example.base.simplekicker.simplekicker;

void run()
{
    import core.time;
    import std.datetime, std.conv;
    import flow.base.dev, flow.base.blocks;

    uint amount = 5;
    uint times = 5;

    debugMsg("#######################################", 0);
    debugMsg("#######################################", 0);
    debugMsg("### "~amount.to!string~" kicker playing ball", 0);
    debugMsg("#######################################", 0);
    auto f =
    {
        auto configStr = "{
            \"dataType\": \"flow.example.base.simplekicker.simplekicker.SimpleKickerConfig\",
            \"amount\": "~amount.to!string~",
            \"times\": "~times.to!string~",
            \"domain\": \"example.simplekicker\"
        }";
        auto config = Data.fromJson(configStr);

        // create a new flow the local swarm runs in
        auto flow = new Flow;

        flow.add(Organ.create(config));

        // wait for an event indicating that swarm can be shut down
        flow.wait();
        
        // shut down local swarm
        flow.stop();
    };

    auto b = benchmark!(f)(1);
    debugMsg("time required for "~times.to!string~" kicks: "
        ~ b[0].usecs.to!string
        ~ "usecs", 0);
    debugMsg("#######################################", 0);
    debugMsg("", 0);
}

/// two kicker playing Ball
unittest
{
    run();
}
