module flow.causal.main;

import flow.blocks;
import flow.dev;
import flow.util.web, flow.util.memory;

int main(string[] args)
{
    import std.conv, std.file, std.path, std.string, std.stdio;

    version(windows)
    {
        //import std.process;
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
        writeln("could not find web organ configuration \"web.json\" in configuration directory -> exiting");
        return -1;
    }

    if(!ccFile.exists)
    {
        writeln("could not find causal organ configuration \"causal.json\" in configuration directory -> exiting");
        return -1;
    }

    auto wc = Data.fromJson(wcFile.readText);
    auto cc = Data.fromJson(ccFile.readText);

    auto process = new Process;
    process.tracing = true;

    auto wo = Organ.create(wc);
    process.add(wo);

    auto so = Organ.create(cc);
    process.add(so);

    process.wait();

    process.stop();

    return 0;
}
