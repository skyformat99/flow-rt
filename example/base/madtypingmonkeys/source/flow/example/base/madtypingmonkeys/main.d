import flow.example.base.madtypingmonkeys.test;

void main(string[] args)
{
    import std.conv;
    
    auto amount = args.length > 1 ? args[1].to!uint : 10;
    auto search = args.length > 2 ? args[2] : "fo";

    run(amount, search);
}