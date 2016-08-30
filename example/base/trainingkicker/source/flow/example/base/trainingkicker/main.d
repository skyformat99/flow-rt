import flow.example.base.trainingkicker.test;

void main(string[] args)
{
    import std.stdio;
    import std.conv;
    
    auto tracing = false;
    if(args.length > 2)
        tracing = args[2].to!bool;
    
    run(args[1].to!int, tracing);
}