module flow.base.dev;

import __flow.exception, __flow.data;

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
    public static immutable DEBUGSEP = "--------------------------------------------------"~newline;
    public static DL debugLevel = DL.Warning;
    public static void msg(DL level, string msg) {
        if(level <= debugLevel) {
            auto t = "["~level.to!string~"] ";
            t ~= msg;

            synchronized {
                writeln(t);
                //flush();
            }
        }
    }

    public static void msg(DL level, Exception ex, string msg=string.init) {
        string t;
        
        if(msg != string.init)
            t ~= msg~newline~"    ";
        
        if(ex.msg != string.init)
            t ~= ex.msg~newline;

        if(cast(FlowException)ex !is null && (cast(FlowException)ex).data !is null) {
            t ~= DEBUGSEP;
            t ~= (cast(FlowException)ex).data.json~newline;
            t ~= DEBUGSEP;
            t ~= DEBUGSEP;
        }
    }

    public static void msg(DL level, Data d, string msg = string.init) {
        auto t = msg;
        t ~= Debug.DEBUGSEP;
        t ~= d.json;
        Debug.msg(level, t);
    }
}