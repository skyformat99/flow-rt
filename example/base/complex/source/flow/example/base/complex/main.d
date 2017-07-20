module flow.example.base.complex;

import flow.base.blocks, flow.base.data, flow.base.signals, flow.base.dev;

import core.thread, core.cpuid;
import std.conv, std.file, std.path, std.string, std.datetime, std.getopt;
import core.stdc.stdlib;

class SystemDescription : Data {
    mixin data;

    mixin list!(EntityMeta, "entities");
}

class ComplexRelation : Data {
    mixin data;

    mixin field!(EntityPtr, "target");
    mixin field!(double, "power");
}

class CoreComplexContext : Data {
    mixin data;

    mixin list!(ComplexRelation, "relations");
}

class Act : Unicast {
    mixin signal;

    mixin field!(double, "power");
}

class React : Tick {
    mixin tick;

    override void run() {
        import std.random;

        auto s = this.signal.as!Act;
        auto c = this.context.as!CoreComplexContext;

        double amount;
        double overall;
        ComplexRelation[double] map;
        foreach(r; c.relations) {
            // increasing sources power in own wirklichkeit
            if(s.source !is null && r.target.eq(s.source) && s.power !is double.init)
                r.power = r.power + s.power;

            // filling parameters for roulette game if its in own wirklichkeit
            auto p = r.power;
            auto t = r.target;

            if(p > 0) {
                map[overall] = r;
                overall += p;
                amount++;
            }
        }

        auto hit = uniform(0, overall);
        // increasing own power in determined complex's wirklichkeit and decrease its power in own wirklichkeit
        foreach(p; map.keys) {
            if(hit >= p) {
                auto ns = new Act;
                auto power = overall/amount;
                ns.power = power;
                map[p].power = map[p].power - power;
                this.send(ns, map[p].target);
                break;
            }
        }
    }
}

class CoreComplex : Entity {
    mixin entity;

    mixin listen!(fqn!Act, fqn!React);
}

bool stopped = false;
string confDir;
string name;
string domain;
size_t amount;
double init = double.max/2;
bool force;
int threads;

void stop() {
    stopped = true;
}

void main(string[] args) {
    version(posix) sigset(SIGINT, &stop);

    version(windows)
    {
        //import std.flow;
        //dataDir = environment.get("APPDATA");
        Debug.msg(DL.Fatal, "this software doesn't support windows based systems!");
        exit(-1);
    }

    confDir = thisExePath.dirName.buildPath("etc");    
    if(!confDir.exists)
    {
        Debug.msg(DL.Fatal, "could not find configuration directory -> exiting");
        exit(-1);
    }

    threads = threadsPerCPU()-1;

    auto rslt = getopt(args,
        "n|name", "Name of system, obligate", &name,
        "d|domain", "Domain of entities, useful for merging systems", &domain,
        "a|amount", "Sets the amount of generated complexes", &amount,
        "f|force", "Enforce behaviour, in most cases means to overwrite something", &force,
        "i|init", "Initial relation power", &init,
        "t|threads", "Amount of threads to use for running this flow", &threads);

    if(args.length > 1)
        switch(args[1]) {
            case "create":
                create();
                break;
            case "run":
                run();
                break;
            default:
                help(rslt);
                break;
        }
    else help(rslt);

    exit(0);
}

void help(GetoptResult rslt) {
    defaultGetoptPrinter("Sample complex System.\n"~
            "[Actions]\n"~
            "create\tCreates a system using given parameters\n"~
            "run\tRuns given system from latest available snapshot or original description if no snapshot is found\n"~
            "\n[Options]", rslt.options);
}

void create() {
    if(name == string.init) {
        Debug.msg(DL.Fatal, "you have to set a valid name using --name -> exiting");
        exit(-1);
    }

    auto descFile = confDir.buildPath(name~".json");
    if(descFile.exists) {
        if(force) {
            descFile.remove();
        } else {
            Debug.msg(DL.Fatal, "complex snapshot \""~name~".json\" is already existing (use --force for overwrite) -> exiting");
            exit(-1);
        }
    }

    if(amount < 2) {
        Debug.msg(DL.Fatal, "you have to set an amount of complexes greater 1 using --amount -> exiting");
        exit(-1);
    }

    auto desc = new SystemDescription();
    
    for(size_t i = 0; i < amount; i++) {
        auto m = new EntityMeta;
        m.info = new EntityInfo;
        m.info.ptr = new EntityPtr;
        m.info.ptr.id = i.to!string;
        m.info.ptr.type = "flow.example.base.complex.CoreComplex";
        m.info.ptr.domain = domain;
        m.info.space = EntitySpace.Local;
        m.info.config = new EntityConfig;
        m.context = new CoreComplexContext;
        m.inbound.put(new Act);
        desc.entities.put(m);
    }

    foreach(m1; desc.entities) {
        foreach(m2; desc.entities) {
            if(m1 != m2) {
                auto r = new ComplexRelation;
                r.target = m2.info.ptr;
                r.power = init;
                m1.context.as!CoreComplexContext.relations.put(r);
            }
        }
    }

    descFile.write(desc.json);

    Debug.msg(DL.Message, "successfully created system "~name);
}

void run() {
    if(name == string.init) {
        Debug.msg(DL.Fatal, "you have to set a valid name using --name -> exiting");
        exit(-1);
    }

    auto descFile = confDir.buildPath(name~".json");
    if(!descFile.exists) {
        Debug.msg(DL.Fatal, "could not find complex description \""~name~".json\" -> exiting");
        exit(-1);
    }

    if(threads < 1) {
        Debug.msg(DL.Fatal, "cannot run using less than 1 thread");
        exit(-1);
    }

    Debug.msg(DL.Message, "loading...");
    auto oldestDt = SysTime.min;
    string oldestSnap;
    foreach(de; confDir.dirEntries(SpanMode.shallow)) {
        if(de.baseName.stripExtension().stripExtension() == name) {
            auto dtString = de.baseName.stripExtension().extension;
            if(dtString != string.init) {
                auto dt = SysTime.fromISOExtString(dtString[1..$]);
                if(dt > oldestDt) {
                    oldestDt = dt;
                    oldestSnap = de;
                }
            }
        }
    }

    string descString = (oldestSnap != string.init ? oldestSnap : descFile).readText;
    auto desc = Data.fromJson(descString).as!SystemDescription;

    auto fc = new FlowConfig;
    fc.worker = threads;
    fc.tracing = true;

    Debug.msg(DL.Message, "running...");
    auto flow = new Flow(fc);
    flow.add(desc.entities.array);

    size_t loopCnt = 0;
    while(!stopped) {
        Thread.sleep(100.msecs);

        if(loopCnt % 100 == 0)
            snap(flow, desc.dup);
    }

    flow.suspend();
    snap(flow, desc.dup);
    Debug.msg(DL.Message, "shutting down...");
    flow.dispose();
}

void snap(Flow flow, SystemDescription desc) {
    desc.entities.clear();
    desc.entities.put(flow.snap());
    auto snapFile = confDir.buildPath(name~"."~Clock.currTime.toISOExtString()~".json");
    if(snapFile.exists) snapFile.remove();
    snapFile.write(desc.json);
}