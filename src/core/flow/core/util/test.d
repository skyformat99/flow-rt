module flow.core.util.test;

version(unittest) {
    import std.stdio;

    void header(string title) {
        writeln("**********************************************************************");
        writeln(title);  
    }

    void footer() {
        writeln("______________________________________________________________________");
    }

    void write(S...)(S msg) {
        writeln('\t', msg);
    }
}