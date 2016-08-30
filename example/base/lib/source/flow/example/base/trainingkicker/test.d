module flow.example.base.trainingkicker.test;
import flow.example.base.trainingkicker.trainedkicker;
import flow.example.base.trainingkicker.trainer;
import flow.example.base.trainingkicker.signals;

void run(uint times, uint amount)
{
    import core.time;
    import std.datetime, std.conv, std.stdio;
    import flow.dev, flow.blocks;

    debugMsg("#######################################", 0);
    debugMsg("#######################################", 0);
    debugMsg("### "~amount.to!string~" kicker playing ball and one trainer", 0);
    debugMsg("### watching and controlling the kicker", 0);
    debugMsg("#######################################", 0);
    auto f =
    {
        auto configStr = "{
            \"dataType\": \"flow.example.base.trainingkicker.trainingkicker.TrainingKickerConfig\",
            \"amount\": "~amount.to!string~",
            \"times\": "~times.to!string~",
            \"domain\": \"example.trainingkicker\"
        }";
        auto config = Data.fromJson(configStr);

        // create a new process the local swarm runs in
        auto process = new Process;
        
        process.add(Organ.create(config));

        // wait for an event indicating that swarm can be shut down
        process.wait();

        // shut down local swarm
        process.stop();
    };

    
    auto b = benchmark!(f)(1);
    debugMsg("time required for "
        ~ times.to!string
        ~ " kicks: " ~ b[0].usecs.to!string
        ~ "usecs", 0);
    debugMsg("#######################################", 0);
    debugMsg("", 0);
}

/** two kicker playing ball and one trainer
watching and controlling the kicker */
unittest
{
    run(10, 5);
}