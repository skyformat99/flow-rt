module flow.base.dev;

import __flow.exception;

import core.time, std.stdio, std.ascii, std.conv;

immutable Duration WAITINGTIME = 5.msecs;

enum DL : uint {
    Fatal = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Debug = 4
}

class Debug {
    private static immutable DEBUGSEP = "--------------------------------------------------"~newline;
    public static DL debugLevel = DL.Warning;
    public static void msg(DL level, string msg=string.init, Exception ex = null) {
        import std.ascii;

        if(level <= debugLevel) {
            auto t = "["~level.to!string~"] ";
            if(msg != string.init)
                t ~= msg~newline~"    ";
            
            if(ex !is null) {
                if(ex.msg != string.init)
                    t ~= ex.msg~newline;

                if(cast(FlowException)ex !is null && (cast(FlowException)ex).data !is null) {
                    t ~= DEBUGSEP;
                    t ~= (cast(FlowException)ex).data.toJson()~newline;
                    t ~= DEBUGSEP;
                    t ~= DEBUGSEP;
                }
            }

            synchronized {
                writeln(t);
                //flush();
            }
        }
    }
}