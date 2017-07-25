module flow.example.base.complex;

import flow.base.blocks, flow.base.data, flow.base.signals, flow.base.dev;

import core.thread, core.cpuid;
import std.conv, std.file, std.path, std.string, std.datetime, std.getopt;
import core.stdc.stdlib;

class SystemDescription : Data {
    mixin data;

    mixin list!(Entity, "entities");
}

class ComplexRelation : Data {
    mixin data;

    mixin field!(EntityPtr, "entity");
    mixin field!(size_t, "power");
}

class CoreComplexContext : Data {
    mixin data;

    mixin list!(ComplexRelation, "relations");
}

class ReactData : Data {
    mixin data;

    mixin field!(ComplexRelation, "source");
    mixin field!(size_t, "sourcePower");
    mixin field!(ComplexRelation, "target");
    mixin field!(size_t, "targetPower");
    mixin field!(size_t, "overall");
}

class Act : Unicast {
    mixin signal;

    mixin field!(size_t, "power");
}

/*class Apply : Tick {
    mixin tick;

    override void run() {
        auto s = this.signal.as!Act;
        auto c = this.context.as!CoreComplexContext;

        foreach(r; c.relations) {
            // increasing sources power in own wirklichkeit
            if(s.source !is null && r.target.eq(s.source)) {
                r.power = r.power + s.power;
                break;
            }
        }

        this.next(fqn!Search);
    }
}

class Search : Tick {
    mixin tick;

    override void run() {
        import std.random;

        auto c = this.context.as!CoreComplexContext;

        size_t amount;
        size_t overall = 0;
        ComplexRelation[size_t] map;
        foreach(r; c.relations) {
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
        ComplexRelation target;
        // increasing own power in determined complex's wirklichkeit and decrease its power in own wirklichkeit
        foreach(p; map.keys) {
            if(hit >= p) {
                target = map[p];
                break;
            }
        }

        if(target !is null)
            this.next(fqn!DoAct, target);
    }
}

class DoAct : Tick {
    mixin tick;

    override void run() {
        auto d = this.data.as!ComplexRelation;

        auto ns = new Act;
        ns.power = 1;
        d.power = d.power - ns.power;
        this.send(ns, d.target);
    }
}*/

class React : Tick {
    mixin tick;

    override void run() {
        import std.random;

        auto s = this.signal.as!Act;
        auto c = this.context.as!CoreComplexContext;

        size_t amount;
        size_t overall = 0;
        ComplexRelation[size_t] map;
        auto d = new ReactData;
        foreach(r; c.relations.dup) {
            if(s.source !is null && r.entity.eq(s.source)) {
                d.source = r;
                d.sourcePower = s.power;
            }

            auto p = r.power;
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
                d.target = map[p];
                break;
            }
        }

        d.targetPower = 1;

        this.next(fqn!Do, d);
    }
}

class Do : Tick {
    mixin sync;

    override void run() {
        auto d = this.data.as!ReactData;

        if(d.source !is null)
            d.source.power = d.source.power + d.sourcePower;

        auto ns = new Act;
        ns.power = d.targetPower;
        d.target.power = d.target.power - ns.power;
        this.send(ns, d.target.entity);
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
size_t init = 1;
bool force;
int threads;

extern (C) void stop(int signal) {
    stopped = true;
    Log.msg(LL.Message, "stopping...");
}

void main(string[] args) {
    confDir = thisExePath.dirName.buildPath("etc");    
    if(!confDir.exists)
    {
        Log.msg(LL.Fatal, "could not find configuration directory -> exiting");
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
        Log.msg(LL.Fatal, "you have to set a valid name using --name -> exiting");
        exit(-1);
    }

    auto descFile = confDir.buildPath(name~".json");
    if(descFile.exists) {
        if(force) {
            descFile.remove();
        } else {
            Log.msg(LL.Fatal, "complex snapshot \""~name~".json\" is already existing (use --force for overwrite) -> exiting");
            exit(-1);
        }
    }

    if(amount < 2) {
        Log.msg(LL.Fatal, "you have to set an amount of complexes greater 1 using --amount -> exiting");
        exit(-1);
    }

    auto desc = new SystemDescription();
    
    for(size_t i = 0; i < amount; i++) {
        auto m = new Entity;
        m.info = new EntityInfo;
        m.info.ptr = new EntityPtr;
        m.info.ptr.id = i.to!string;
        m.info.ptr.type = "flow.example.base.complex.CoreComplex";
        m.info.ptr.domain = domain;
        m.info.space = Access.Local;
        m.info.config = new EntityConfig;
        m.context = new CoreComplexContext;
        m.inbound.put(new Act);
        desc.entities.put(m);
    }

    foreach(m1; desc.entities) {
        foreach(m2; desc.entities) {
            if(m1 != m2) {
                auto r = new ComplexRelation;
                r.entity = m2.info.ptr;
                r.power = init;
                m1.context.as!CoreComplexContext.relations.put(r);
            }
        }
    }

    descFile.write(desc.json);

    Log.msg(LL.Message, "successfully created system "~name);
}

void run() {
    static import core.sys.posix.signal;
    core.sys.posix.signal.sigset(core.sys.posix.signal.SIGINT, &stop);

    if(name == string.init) {
        Log.msg(LL.Fatal, "you have to set a valid name using --name -> exiting");
        exit(-1);
    }

    auto descFile = confDir.buildPath(name~".json");
    if(!descFile.exists) {
        Log.msg(LL.Fatal, "could not find complex description \""~name~".json\" -> exiting");
        exit(-1);
    }

    if(threads < 1) {
        Log.msg(LL.Fatal, "cannot run using less than 1 thread");
        exit(-1);
    }

    Log.msg(LL.Message, "loading...");
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

    Log.msg(LL.Message, "running...");
    auto flow = new Flow(fc);
    flow.add(desc.entities.array);

    size_t loopCnt = 0;
    while(!stopped && loopCnt < 100) {
        Thread.sleep(100.msecs);
        //loopCnt++;
    }

    Log.msg(LL.Message, "suspending...");
    flow.suspend();
    Log.msg(LL.Message, "snapping...");
    snap(flow, desc.dup);
    Log.msg(LL.Message, "shutting down...");
    flow.dispose();
}

void snap(Flow flow, SystemDescription desc) {
    desc.entities.clear();
    desc.entities.put(flow.snap());
    auto snapFile = confDir.buildPath(name~"."~Clock.currTime.toISOExtString()~".json");
    if(snapFile.exists) snapFile.remove();
    snapFile.write(desc.json);
}