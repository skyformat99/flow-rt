module __flow.log;

import __flow.data;
import __flow.error;

import std.stdio, std.ascii, std.conv, std.json;

enum LL : uint {
    Message = 1 << 0,
    Fatal = 1 << 1,
    Error = 1 << 2,
    Warning = 1 << 3,
    Info = 1 << 4,
    Debug = 1 << 5,
    FDebug = 1 << 6
}

class Log {
    public static immutable sep = newline~"--------------------------------------------------"~newline;
    public static LL logLevel = LL.Message | LL.Fatal | LL.Error | LL.Warning;
    public static void msg(LL level, string msg) {
        if(level & logLevel) {
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
            t ~= (cast(FlowException)ex).data.json.toString~newline;
            t ~= sep;
            t ~= sep;
        }

        Log.msg(level, t);
    }

    public static void msg(LL level, Data d, string msg = string.init) {
        auto t = msg;
        t ~= Log.sep;
        t ~= d !is null ? d.json.toString : "NULL";
        Log.msg(level, t);
    }
}