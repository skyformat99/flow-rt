struct SomeInfo {
    string t;
}

struct SomeOtherInfo {
    int x;
}

struct AllInfo {
    private SomeInfo sI;
    private SomeOtherInfo sOI;
    alias sI this;
    alias sOI this;
}

void main() {
    import std.range;

    AllInfo all;
    all.t = "foo";
    all.x = 5;

    assert(all.t == "foo" && all.x == 5);
}
