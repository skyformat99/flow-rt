module flow.base.dev;

import __flow.exception, __flow.data;

import core.time, std.stdio, std.ascii, std.conv;

immutable Duration WAITINGTIME = 5.msecs;

enum DL : uint {
    Message = 0,
    Fatal = 1,
    Error = 2,
    Warning = 3,
    Info = 4,
    Debug = 5,
    FDebug = 6
}

class Debug {
    public static immutable sep = newline~"--------------------------------------------------"~newline;
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
            t ~= sep;
            t ~= (cast(FlowException)ex).data.json~newline;
            t ~= sep;
            t ~= sep;
        }
    }

    public static void msg(DL level, Data d, string msg = string.init) {
        auto t = msg;
        t ~= Debug.sep;
        t ~= d.json;
        Debug.msg(level, t);
    }
}