module flow.run;

bool stopped = false;

extern (C) void stop(int signal) {
    import flow.core.util;
    import core.stdc.stdlib;

    if(!stopped)
        stopped = true;
    else {
        Log.msg(LL.Fatal, "requested force exit");
        exit(-1);
    }
    Log.msg(LL.Message, "stopping...");
}

extern (C) void die(int signal) {
    import flow.core.util;
    import core.stdc.stdlib;

    Log.msg(LL.Fatal, "Memory access error (SIGSEGV) occured -> exiting");
    exit(-999);
}

int main(string[] args) {
    import flow.core.util;
    import core.stdc.stdlib;
    import std.stdio, std.file, std.path, std.process, std.algorithm, std.algorithm.searching;

    version(Posix) {
        string confDir, libDir, path;

        // checking arguments
        if(args.length == 2) {
            if(args[1] == "-h" || args[1] == "--help") {
                writeln("Usage: flow-run [path/name]");
                return 0;
            }
            else
                path = args[1];
        }
        else {
            writeln("Usage: flow-run [path/name]");
            return 1;
        }

        // building configuration directory info
        if(path.absolutePath.isDir)
            confDir = path.absolutePath;
        else if(environment.get("FLOW_CONFIG_DIR").isDir)
            confDir = environment.get("FLOW_CONFIG_DIR").buildPath(path);
        else if(thisExePath.dirName.buildPath("etc").isDir)
            confDir = thisExePath.dirName.buildPath("etc").buildPath(path);
        else
            confDir = "/etc".buildPath("flow").buildPath(path);
        
        // checking if given config directory contains process config and at least one space meta
        if(!confDir.isDir ||
            !confDir.dirEntries(SpanMode.shallow).any!(a => a.baseName == "process.cfg") ||
            !confDir.dirEntries(SpanMode.shallow).any!(a => a.baseName == "libs.lst") ||
            !confDir.dirEntries(SpanMode.shallow).any!(a => a.extension == ".spc")) {
            Log.msg(LL.Fatal, "could not find configuration directory -> exiting");
            exit(-1);
        }

        // building and checking flow library directory info
        if(environment.get("FLOW_EXT_DIR") != string.init)
            libDir = environment.get("FLOW_EXT_DIR");
        else {
            libDir = thisExePath.dirName.buildPath("ext");
            if(!libDir.isDir ||
                !libDir.dirEntries(SpanMode.shallow)
                .any!(
                    a => a.extension == ".so" &&
                    a.baseName(".so") != "libflow-base" &&
                    a.baseName.startsWith("libflow-")))
                libDir = "/etc".buildPath("flow");
        }
        
        if(!libDir.isDir) {
            Log.msg(LL.Fatal, "could not find library directory -> exiting");
            exit(-1);
        }

        // everything ok so far, run
        run(confDir, libDir);
    } else {
        Log.msg(LL.Fatal, "This software doesn't support operating systems not implementing the posix standard!");
        exit(-1);
    }

    return 0;
}

void run(string confDir, string libDir) {
    import flow.core.util, flow.core.data, flow.core;
    import core.stdc.stdlib, core.sys.posix.dlfcn, core.thread;
    import std.string, std.array, std.algorithm.iteration, std.file, std.path;

    static import core.sys.posix.signal;
    core.sys.posix.signal.sigset(core.sys.posix.signal.SIGINT, &stop);

    static import core.stdc.signal, core.sys.posix.signal;
    core.sys.posix.signal.sigset(core.stdc.signal.SIGSEGV, &die);

    auto procFile = confDir.buildPath("process.cfg");
    auto libsFile = confDir.buildPath("libs.lst");
    auto spcFiles = confDir.dirEntries(SpanMode.shallow).filter!(a => a.extension == ".spc");

    Log.msg(LL.Message, "loading libraries...");
    foreach(lib; libsFile.readText.split)
        dlopen(libDir.buildPath(lib).toStringz, RTLD_NOW|RTLD_GLOBAL);

    Log.msg(LL.Message, "initializing process");    
    auto p = new Process();
    scope(exit) p.dispose;

    Log.msg(LL.Message, "initializing spaces");
    Space[] spaces;
    foreach(spcFile; spcFiles) {
        auto spcString = spcFile.readText;
        auto sm = createDataFromJson(spcString).as!SpaceMeta;

        if(sm is null) {
            Log.msg(LL.Fatal, "space meta \""~spcFile~"\" is invalid -> exiting");
            exit(-1);
        }

        spaces ~= p.add(sm);
    }

    // starting spaces
    Log.msg(LL.Message, "ticking...");
    foreach(s; spaces)
        s.tick();

    //auto cnt = 0;
    // watiting for sigint (ctrl+c)
    while(!stopped/* && cnt < 100*/) {
        Thread.sleep(5.msecs);
        //cnt++;
    }

    // stopping spaces
    Log.msg(LL.Message, "freezing...");
    foreach(s; spaces)
        s.freeze();

    // serializing spaces to disk
    Log.msg(LL.Message, "snapping...");
    foreach(s; spaces) {
        auto sm = s.snap;
        confDir.buildPath(sm.id).setExtension(".spc").write(sm.json(true));
    }

    version (MemoryErrorSupported)
        deregisterMemoryErrorHandler();
}