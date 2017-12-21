import std.file, std.path, std.json, std.compiler;

static if(vendor == Vendor.digitalMars) {
    immutable DC = "dmd";
    immutable LD = "dmd";
} else static if(vendor == Vendor.llvm) {
    immutable DC = "ldc";
    immutable LD = "ldc";
} else static assert(false, "!!! supporting only dmd and ldc yet");

static if(vendor == Vendor.digitalMars) {
    version(Posix) {
        immutable defaultlib = "libphobos2.so";
        debug {immutable defCflags = ["-c","-debug","-g","-fPIC","-vcolumns","-w","-defaultlib="~defaultlib];}
        else {immutable defCflags = ["-c","-fPIC","-w","-defaultlib="~defaultlib];}
        immutable defLflags = ["-L-l:"~defaultlib];
    }
    version(Windows) {
        immutable defaultlib = "libphobos2.dll";
        debug {immutable defCflags = ["-c","-debug","-g","-vcolumns","-w","-defaultlib="~defaultlib];}
        else {immutable defCflags = ["-c","-w","-defaultlib="~defaultlib];}
        immutable defLflags = ["-L-l:"~defaultlib];
    }
} else static if(vendor == Vendor.llvm) {
    version(Posix) {immutable defaultlib = "libphobos2-ldc.so"; }
    version(Windows) {immutable defaultlib = "libphobos2-ldc.dll"; }
    
    debug {immutable defCflags = ["-c","-d-debug","-g","-vcolumns","-w","-defaultlib="~defaultlib];}
    else {immutable defCflags = ["-c","-w","-defaultlib="~defaultlib];}
    immutable defLflags = ["-L-l:"~defaultlib];
}

string rootDir;

T get(T)(JSONValue j, string f, T def = T.init) {
    import std.conv : to;
    import std.range : isArray, ElementType, array;
    import std.algorithm.iteration : map;
    
    if(f in j) {
        static if(isArray!T && !is(T==string))
            return j[f].array.map!(ja => ja.str.to!(ElementType!T)).array;
        else return j[f].str.to!T;
    } else return def;
}

enum LinkType {
    Static,
    Shared,
    Bin
}

class Build {
    static Build[string] reg;

    static void make() {
        foreach(n, b; reg)
            if(!b.done && b.flow)
                b.exec();
    }

    version(Posix) {
        immutable staticExt = ".a";
        immutable sharedExt = ".so";
        immutable binExt = string.init;
    }
    version(Windows) {
        immutable staticExt = ".lib";
        immutable sharedExt = ".dll";
        immutable binExt = ".exe";
    }

    string name;
    LinkType type;
    string main;
    bool flow;
    string root;
    string limit;
    string[] deps;
    string[] cflags;
    string[] lflags;
    string[] posixlibs;
    string[] winlibs;
    bool done = false;
    bool clean = false;

    this(string n, LinkType t, string m, bool f, string j) {
        this.name = n;
        this.type = t;
        this.main = m;
        this.flow = f;

        this.load(j);
    }

    final void load(string js) {
        import std.range : empty;

        auto j = parseJSON(js);
        this.root = j.get!string("root");
        this.limit = j.get!string("limit");
        this.deps = j.get!(string[])("deps");
        this.cflags = j.get!(string[])("cflags");
        this.lflags = j.get!(string[])("lflags");
        this.posixlibs = j.get!(string[])("posixlibs");
        this.winlibs = j.get!(string[])("winlibs");
    }

    final bool check(string f) {
        import std.datetime.systime;

        if(!f.exists) return false;

        SysTime tt, ft;
        f.getTimes(tt, ft);

        foreach(s; this.src) {
            SysTime st;
            this.srcRoot.buildPath(s).getTimes(tt, st);

            if(st > ft)
                return false;
        }

        return true;
    }

    final bool checkDeps() {
        foreach(d; this.deps) {
            assert(d in reg, "!!! dependecy \""~d~"\" of \""~this.of~"\" not found");
            
            if(!Build.reg[d].clean)
                return false;
        }

        return true;
    }

    final string[] src() @property {
        import std.range : array;
        import std.algorithm.iteration : map;
        auto limitDir = this.srcRoot.buildPath(this.limit);
        return limitDir.dirEntries("*.d", SpanMode.depth).map!(x => x.relativePath(this.srcRoot)).array;
    }

    final string of() @property {
        if(this.type == LinkType.Static)
            return rootDir.buildPath("lib", "lib"~this.name~staticExt);
        else if(this.type == LinkType.Shared)
            return rootDir.buildPath("lib", "lib"~this.name~sharedExt);
        else return rootDir.buildPath("bin", "flow-"~this.name~binExt);
    }

    final string obj() @property {
        version(Posix)
            return rootDir.buildPath("obj", this.name~".o");
        version(Windows)
            return rootDir.buildPath("obj", this.name~".obj");
    }

    final string srcRoot() @property {return this.main.buildPath(this.root);}
    
    final string[] depCflags() @property {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Build.reg[d].depCflags;

        if(!this.flow)
            flags ~= ["-I"~this.srcRoot];
        return flags;
    }

    final string[] buildCflags() @property {
        string[] flags = cast(string[])defCflags;

        if(this.flow && this.type != LinkType.Bin)
            flags ~= ["-op", "-Hd="~rootDir.buildPath("ifc")];

        foreach(d; this.deps)
            flags ~= Build.reg[d].depCflags;

        return flags~["-I"~rootDir.buildPath("ifc")];
    }

    version(Posix) final string[] libsLflags() @property {
        string[] flags;
        foreach(l; this.posixlibs)
            flags ~= ["-L-l:"~l];
        return flags;
    }
    
    version(Win32) final string[] libsLflags() @property {
        string[] flags;
        foreach(l; this.winlibs)
            flags ~= [rootDir.buildPath("dist", "x86", l)];
        return flags;
    }
    
    version(Win64) final string[] libsLflags() @property {
        string[] flags;
        foreach(l; this.winlibs)
            flags ~= [rootDir.buildPath("dist", "x86_64", l)];
        return flags;
    }

    version(Posix) final string[] depLflags() @property {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Build.reg[d].depLflags;

        return flags~this.libsLflags~["-L-l:"~this.of.baseName];
    }

    version(Windows) final string[] depLflags() @property {
        string[] flags;
        foreach(d; this.deps)
            flags ~= Build.reg[d].depLflags;

        return flags~this.libsLflags~[this.of];
    }

    final string[] buildLflags() @property {
        string[] flags = cast(string[])defLflags;

        flags ~= this.libsLflags;

        if(this.type == LinkType.Shared)
            flags ~= "-shared";
        else if(this.type == LinkType.Static)
            flags ~= "-lib";

        foreach(d; this.deps)
            flags ~= Build.reg[d].depLflags;

        return flags~["-L-L"~rootDir.buildPath("lib")];
    }

    final void buildDeps() {
        foreach(d; this.deps) {
            assert(d in reg, "!!! dependecy \""~d~"\" of \""~this.of~"\" not found");
            
            if(!Build.reg[d].done)
                Build.reg[d].exec();
        }
    }

    void exec() {
        import std.stdio : writeln;

        this.buildDeps();

        writeln("*** building \""~this.of~"\"");
        this.clean = this.check(this.obj) && this.checkDeps();
        if(!this.clean) {
            this.compile(this.cflags, this.obj);
            this.link(this.lflags, this.obj, this.of);
        } else writeln("+++ up to date");

        this.done = true;
    }

    final void compile(string[] cflags, string obj) {
        import std.conv : to;
        import std.datetime.stopwatch : benchmark;
        import std.range : array;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.process : spawnProcess, wait, Config;
        // search path for source files

        auto f = {
            auto dcPid = spawnProcess(
                [DC, "-of"~obj]~this.buildCflags~cflags~this.src,
                stdin, stdout, stderr, null, Config.none, this.srcRoot);
            assert(dcPid.wait() == 0, "!!! compiling error");
        };

        auto b = benchmark!(f)(1);
        writeln("+++ ", b[0]);        
    }

    final void link(string[] lflags, string obj, string of) {
        import std.datetime.stopwatch : benchmark;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.process : spawnProcess, wait, Config;
        
        auto ldPid = spawnProcess(
            [LD, "-of"~of]~this.buildLflags~lflags~[obj],
            stdin, stdout, stderr, null, Config.none, this.srcRoot);
        assert(ldPid.wait() == 0, "!!! linking error");      
    }
}

class Test : Build {
    static Test[string] reg;

    static void run() {
        foreach(n, t; reg)
            t.exec();
    }

    this(string n, string m, string j) {
        super(n, LinkType.Bin, m, false, j);
    }

    final string testOf() @property {
        return rootDir.buildPath("test", this.name~binExt);
    }

    final string testObj() @property {
        version(Posix)
            return rootDir.buildPath("test", "obj", this.name~".o");
        version(Windows)
            return rootDir.buildPath("test", "obj", this.name~".obj");
    }

    override void exec() {
        import std.stdio : writeln;

        writeln("*** testing \""~this.testOf~"\"");
        this.clean = this.check(this.testObj) && this.checkDeps();
        if(!this.clean) {
            this.compile(this.cflags~["-unittest", "-main"], this.testObj);
            this.link(this.lflags, this.testObj, this.testOf);
        }

        this.test(this.testOf);

        this.done = true;
    }

    void test(string test) {
        import core.time;
        import std.conv : to;
        import std.datetime.stopwatch : benchmark;
        import std.stdio : stdin, stdout, stderr, writeln;
        import std.process : spawnProcess, wait, Config;

        auto f = {
            string[string] env;
            env["LD_LIBRARY_PATH"] = rootDir.buildPath("lib");
            auto tstPid = spawnProcess([test], stdin, stdout, stderr, env, Config.none, rootDir);
            assert(tstPid.wait() == 0, "!!! testing error");
        };

        auto b = benchmark!(f)(1);
        writeln("--- ", b[0]);
    }
}

void loadLibs() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.lib.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".lib.json");
        writeln("*** adding library ", name);
        Build.reg[name] = new Build(name, LinkType.Static, j.dirName.buildPath(name), false, j.readText);
        Test.reg[name] = new Test(name, j.dirName.buildPath(name), j.readText);
    }
}

void loadCore() {
    import std.range : front, empty, array;
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("core.json", SpanMode.depth).array;
    if(!jsons.empty) {
        if(jsons.length > 1) assert("!!! there cannot be multiple core definitions");
        auto j = jsons.front;
        auto name = "core";
        writeln("*** adding flow core");
        Build.reg[name] = new Build(name, LinkType.Shared, j.dirName.buildPath(name), true, j.readText);
        Test.reg[name] = new Test(name, j.dirName.buildPath(name), j.readText);
    }
}

void loadExts() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.ext.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".ext.json");
        writeln("*** adding extension ", name);
        Build.reg[name] = new Build(name, LinkType.Shared, j.dirName.buildPath(name), true, j.readText);
        Test.reg[name] = new Test(name, j.dirName.buildPath(name), j.readText);
    }
}

void loadBins() {
    import std.stdio : writeln;

    auto jsons = rootDir.dirEntries("*.bin.json", SpanMode.depth);
    foreach(j; jsons) {
        auto name = j.baseName(".bin.json");
        writeln("*** adding binary ", name);
        Build.reg[name] = new Build(name, LinkType.Bin, j.dirName.buildPath(name), true, j.readText);
    }
}

int main(string[] args) {
    import std.stdio : writeln;

    writeln("*** compiling using "~DC);

    rootDir = getcwd;

    auto cmd = args.length > 1 ? args[1] : "build";

    if(cmd == "rebuild" || cmd == "clean") {
        if(rootDir.buildPath("obj").exists)
            rootDir.buildPath("obj").rmdirRecurse;

        if(rootDir.buildPath("ifc").exists)
            rootDir.buildPath("ifc").rmdirRecurse;

        if(rootDir.buildPath("lib").exists)
            rootDir.buildPath("lib").rmdirRecurse;

        if(rootDir.buildPath("bin").exists)
            rootDir.buildPath("bin").rmdirRecurse;

        if(rootDir.buildPath("test").exists)
            rootDir.buildPath("test").rmdirRecurse;
    }

    if(cmd == "build" || cmd == "rebuild") {
        rootDir.buildPath("obj").mkdirRecurse;
        rootDir.buildPath("ifc").mkdirRecurse;
        rootDir.buildPath("lib").mkdirRecurse;
        rootDir.buildPath("bin").mkdirRecurse;
        rootDir.buildPath("test").mkdirRecurse;
        rootDir.buildPath("test", "obj").mkdirRecurse;

        loadLibs();
        loadCore();
        loadExts();
        loadBins();
        
        Build.make();
        Test.run();
    }

    return 0;
}