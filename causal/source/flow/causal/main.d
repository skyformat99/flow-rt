module flow.causal.main;

import flow.base.blocks;
import flow.base.dev;
import flow.base.data;
import flow.net.http, flow.data.memory;

import core.thread;
version(posix) import core.sys.posix.signal;

bool stopped = false;

void stop()
{
    stopped = true;
}

int main(string[] args)
{
    import std.conv, std.file, std.path, std.string, std.stdio;

    version(posix) sigset(SIGINT, &stop);

    version(windows)
    {
        //import std.flow;
        //dataDir = environment.get("APPDATA");
        writeln("this software doesn't support windows based systems yet!");
        return -1;
    }

    auto confDir = thisExePath.dirName.buildPath("etc");

    if(!confDir.exists)
        confDir = "/etc".buildPath(thisExePath.baseName);
    
    if(!confDir.exists)
    {
        writeln("could not find configuration directory -> exiting");
        return -1;
    }

    auto wcFile = confDir.buildPath("web.json");
    auto ccFile = confDir.buildPath("causal.json");

    if(!wcFile.exists)
    {
        writeln("could not find web configuration \"web.json\" in configuration directory -> exiting");
        return -1;
    }

    if(!ccFile.exists)
    {
        writeln("could not find causal configuration \"causal.json\" in configuration directory -> exiting");
        return -1;
    }

    writeln("loading configuration...");
    auto wc = Data.fromJson(wcFile.readText);
    auto cc = Data.fromJson(ccFile.readText);

    auto fc = new FlowConfig;
    fc.tracing = true;

    writeln("creating swarm...");
    auto flow = new Flow(fc);

    //flow.wait();
    while(!stopped)
        Thread.sleep(dur!("msecs")(100));

    flow.stop();

    return 0;
}
