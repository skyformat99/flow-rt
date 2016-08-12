module flowbase.type.tests;
import flowbase.type.types;

// TODO think about whats untested and implement that unittests
// TODO implement unittests for thread safety

/// test List array instance
unittest
{
    int[] arr = [1, 3, 5];
    auto list = new List!int(arr);
    assert(list[0] == 1);
    assert(list[1] == 3);
    assert(list[2] == 5);
}