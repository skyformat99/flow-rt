module flow.complex.main;

import std.getopt;

private struct ComplexOpts {
    string output;
    bool force;
    string space;
    size_t amount;
    string params;
}

void main(string[] args) {
    import flow.base.engine, flow.base.data, flow.base.std, flow.base.util;
    import std.file;

    ComplexOpts opts;

    auto rslt = getopt(args,
        "o|out",    "Output directory path (OBLIGATE)", &opts.output,
        "f|force",  "Force overwrite", &opts.force,
        "s|space",  "Id of space (OBLIGATE != \"\")", &opts.space,
        "a|amount", "Amount of generated complex core entities (OBLIGATE >2)", &opts.amount,
        "p|param",  "Generation parameter", &opts.params);

    SpaceMeta sm;
    if(args.length > 1 && opts.output != string.init && opts.output.exists && opts.amount > 2)
        switch(args[1]) {
            case "power":
                import flow.complex.power;
                sm = createPower(opts.space, opts.amount, opts.params.parsedParams);
                break;
            default:
                help(rslt);
        }
    else help(rslt);

    if(sm !is null) {
        import std.path, std.array;

        auto outputFile = opts.output.buildPath(opts.space.setExtension(".spc"));
        if(outputFile.exists && opts.force)
            outputFile.remove();
        else Log.msg(LL.Fatal, "output path already contains a space named \""~opts.space~"\" (use -f to overwrite)");

        outputFile.write(sm.json.toPrettyString());

        auto pcFile = opts.output.buildPath("process.cfg");
        if(!pcFile.exists) {
            auto pc = new ProcessConfig;
            pcFile.write(pc.json.toString);
        }

        auto libsFile = opts.output.buildPath("libs.lst");
        if(libsFile.exists) {
            import std.string, std.algorithm.searching;

            if(!libsFile.readText.split.any!(a=>a.strip == "libflow-complex.so"))
                libsFile.append("libflow-complex.so");
        } else {
            libsFile.write("libflow-complex.so\n");
        }
    }
}

private void help(GetoptResult rslt) {
    defaultGetoptPrinter("FLOW complex generator.\n"~
            "[Type]\n"~
            "power\tGenerates a system driven by interacting power.\n"~
            "\n[Options]", rslt.options);
}

private string[string] parsedParams(string paramsString) {
    import std.array;

    string[string] params;

    foreach(pS; paramsString.split('|')) {
        if(pS != string.init) {
            auto pP = pS.split('=');
            if(pP.length == 2)
                params[pP[0]] = pP[1];
        }
    }

    return params;
}