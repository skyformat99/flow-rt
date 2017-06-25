module flow.base.dev;

import core.time, core.sync.mutex, std.stdio, std.ascii;

immutable Duration WAITINGTIME = 5.msecs;

immutable DL_FATAL = 0;
immutable DL_ERROR = 1;
immutable DL_WARNING = 2;
immutable DL_INFO = 3;
immutable DL_DEBUG = 4;
immutable DEBUGSEP = "--------------------------------------------------"~newline;


int debugLevel = DL_WARNING;
Mutex debugLock = new Mutex;

void debugMsg(uint level, string msg=string.init, Exception ex = null) {
    import std.ascii;

    if(level <= debugLevel) {
        auto t = "["~level.to!string~"] ";
        if(msg != string.init)
            t ~= msg~newline~"    ";
        
        if(ex !is null) {
            if(ex.msg != string.init)
                t ~= ex.msg~newline;

            if(cast(FlowException)ex !is null && ex.data !is null) {
                t ~= DEBUGSEP;
                t ~= ex.data.toJson()~newline;
                t ~= DEBUGSEP;
                t ~= DEBUGSEP;
            }
        }

        synchronized(debugLock) {
            writeln(t);
            //flush();
        }
    }
}

void debugMsg(Entity e, uint level, string msg = string.init, Exception ex = null) {
    debugMsg(level, "entity("~e.info.ptr.type~"|"~e.address~"); "~msg, ex);
}

void debugMsg(Entity e, uint level, string msg = string.init, Exception ex = null) {
    debugMsg(level, "entity("~e.info.ptr.type~"|"~e.address~"); "~msg, ex);
}