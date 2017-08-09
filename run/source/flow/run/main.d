module flow.example.base.complex;

bool stopped = false;
string confDir;
string libDir;
string name;

extern (C) void stop(int signal) {
    import flow.base.util;

    stopped = true;
    Log.msg(LL.Message, "stopping...");
}

void main(string[] args) {
    import flow.base.util;
    import std.stdio, std.file, std.path, std.process, std.algorithm, std.algorithm.searching;

    version(windows)
        Log.msg(LL.Fatal, "this software doesn't support windows based systems yet!");

    // checking arguments
    if(args.length > 1 && args[1] != "-h" && args[1] != "--help")
        name = args[1];
    else
        writeln("Usage: flow-run [name]");

    // building configuration directory info
    if(environment["FLOW_CONFIG_DIR"] != string.init)
        confDir = environment["FLOW_CONFIG_DIR"];
    else {
        confDir = thisExePath.dirName.buildPath("config");
        if(!confDir.exists)
            confDir = "/etc".buildPath("flow");
    }
    confDir.buildPath(name);
    
    // checking if given config directory contains process config and at least one space meta
    if(!confDir.exists ||
        !confDir.dirEntries(SpanMode.shallow).any!(a => a.baseName == "process.cfg") ||
        !confDir.dirEntries(SpanMode.shallow).any!(a => a.extension == ".spc"))
        Log.msg(LL.Fatal, "could not find configuration directory -> exiting");

    // building and checking flow library directory info
    if(environment["FLOW_LIB_DIR"] != string.init)
        libDir = environment["FLOW_LIB_DIR"];
    else {
        libDir = thisExePath.dirName.buildPath("lib");
        if(!libDir.exists ||
            !libDir.dirEntries(SpanMode.shallow)
            .any!(
                a => a.extension == ".so" &&
                a.baseName(".so") != "flow-base" &&
                a.baseName.startsWith("flow-")))
            libDir = "/etc".buildPath("flow");
    }
    
    if(!libDir.exists)
        Log.msg(LL.Fatal, "could not find library directory -> exiting");

    // everything ok so far, run
    run();
}

void run() {
    import flow.base.util, flow.base.data, flow.base.engine, flow.data.base;
    import core.thread, std.algorithm.iteration, std.file, std.path;

    static import core.sys.posix.signal;
    core.sys.posix.signal.sigset(core.sys.posix.signal.SIGINT, &stop);

    auto procFile = confDir.buildPath("process.cfg");
    auto spcFiles = confDir.dirEntries(SpanMode.shallow).filter!(a => a.extension == ".spc");

    Log.msg(LL.Message, "loading...");

    // creating process
    auto pc = createData(procFile.readText).as!ProcessConfig;
    if(pc is null)
        Log.msg(LL.Fatal, "process configuration is invalid -> exiting");
    
    auto p = new Process(pc);
    scope(exit) p.destroy;

    // creating spaces
    Space[] spaces;
    foreach(spcFile; spcFiles) {
        auto sm = createData(spcFile.readText).as!SpaceMeta;

        if(sm is null)
            Log.msg(LL.Fatal, "space meta \""~spcFile~"\" is invalid -> exiting");

        spaces ~= p.add(sm);
    }

    // starting spaces
    Log.msg(LL.Message, "ticking...");
    foreach(s; spaces)
        s.tick();

    // watiting for sigint (ctrl+c)
    while(!stopped)
        Thread.sleep(100.msecs);

    // stopping spaces
    Log.msg(LL.Message, "freezing...");
    foreach(s; spaces)
        s.freeze();

    // serializing spaces to disk
    Log.msg(LL.Message, "snapping...");
    foreach(s; spaces) {
        auto sm = s.snap;
        confDir.buildPath(sm.id).write(sm.json.toString());
    }
}