module flow.base.dev;

import core.time;
import std.stdio;

immutable Duration WAITINGTIME = 5.msecs;

immutable DEBUGLEVEL = 7;
void debugMsg(string msg, uint level)
{
    if(level <= DEBUGLEVEL)
        synchronized {
            writeln(msg);
            //flush();
        }
}

/*void debugMsg(S...)(uint level, S args)
{
    if(level <= DEBUGLEVEL)
        writeln(S)(args);
}*/