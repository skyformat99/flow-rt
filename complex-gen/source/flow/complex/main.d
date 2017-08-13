module flow.complex.main;

import std.getopt;

///
private struct ComplexOpts {
    string output;
    bool force;
    string space;
    size_t amount;
    string params;
}

void main(string[] args) {
    import flow.base.data, flow.base.std;
    import std.file;

    ComplexOpts opts;

    auto rslt = getopt(args,
        "o|out",    "Output space file (OBLIGATE)", &opts.output,
        "f|force",  "Force overwrite", &opts.force,
        "s|space",  "Id of space (OBLIGATE != \"\")", &opts.space,
        "a|amount", "Amount of generated complex core entities (OBLIGATE >1)", &opts.amount,
        "p|param",  "Generation parameter", &opts.params);

    SpaceMeta sm;
    if(args.length > 1 && opts.output != string.init && (!opts.output.exists || opts.force) && opts.amount > 1)
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
        if(opts.output.exists && opts.force)
            opts.output.remove();

        opts.output.write(sm.json.toString);
    }
}

private void help(GetoptResult rslt) {
    defaultGetoptPrinter("FLOW complex generator.\n"~
            "[Type]\n"~
            "power\tGenerates a system driver by power interaction.\n"~
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