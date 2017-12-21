module flow.core.util.test;

version(unittest) {
    import std.stdio;

    void header(string title) {
        writeln("\t>>> ", title);
    }

    void footer() {
    }

    void write(S...)(S msg) {
        writeln('\t', msg);
    }
}