module flow.base.dev;

import __flow.data;
import flow.base.error;

import core.time, std.stdio, std.ascii, std.conv;

immutable Duration WAITINGTIME = 5.msecs;

enum LL : uint {
    Message = 0,
    Fatal = 1,
    Error = 2,
    Warning = 3,
    Info = 4,
    Debug = 5,
    FDebug = 6
}

class Log {
    public static immutable sep = newline~"--------------------------------------------------"~newline;
    public static LL logLevel = LL.Warning;
    public static void msg(LL level, string msg) {
        if(level <= logLevel) {
            auto t = "["~level.to!string~"] ";
            t ~= msg;

            synchronized {
                writeln(t);
                //flush();
            }
        }
    }

    public static void msg(LL level, Exception ex, string msg=string.init) {
        string t;
        
        if(msg != string.init)
            t ~= msg~newline~"    ";
        
        if(ex !is null && ex.msg != string.init)
            t ~= ex.msg~newline;

        if(cast(FlowException)ex !is null && (cast(FlowException)ex).data !is null) {
            t ~= sep;
            t ~= (cast(FlowException)ex).data.json~newline;
            t ~= sep;
            t ~= sep;
        }

        Log.msg(level, t);
    }

    public static void msg(LL level, Data d, string msg = string.init) {
        auto t = msg;
        t ~= Log.sep;
        t ~= d !is null ? d.json : "NULL";
        Log.msg(level, t);
    }
}