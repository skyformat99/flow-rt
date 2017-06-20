module flow.test.type;
import __flow.type;

import __flow.data;

version(unittest) class TestClass{int x; this(int x) {this.x = x;}}

version (unittest) class TestData : Data
{
    mixin TData;
    mixin TField!(int, "foo");
}

unittest
{
    assert(isConstructableWith!(int, int));
    assert(!isConstructableWith!(int, int, int));
}

version(unittest) class Test_false_hasDefaultConstructor {this(int x) {int y = x;}}
version(unittest) class Test_true_hasDefaultConstructor {this() {int y = 0;}}
unittest
{
    assert(hasDefaultConstructor!int);
    assert(hasDefaultConstructor!Test_true_hasDefaultConstructor);
    assert(!hasDefaultConstructor!Test_false_hasDefaultConstructor);
}

/// test add int to list
unittest
{
    int[] arr = [1, 3];
    auto list = new List!int(arr);
    list.put(5);
    assert(list[0] == 1 && list[1] == 3 && list[2] == 5, "adding elements failed");
}

/// test add class to list
unittest
{
    TestClass[] arr = [new TestClass(1)];
    auto list = new List!TestClass(arr);
    list.put(new TestClass(3));
    assert(list[0] !is null && list[0].x == 1 && list[1] !is null && list[1].x == 3, "adding elements failed");
}

/// test add data object to data list
unittest
{
    TestData[] arr = [(new TestData).set("foo", 1).as!TestData];
    auto list = new DataList!TestData(arr);
    list.put((new TestData).set("foo", 3).as!TestData);
    assert(list[0] !is null && list[0].foo == 1 && list[1] !is null && list[1].foo == 3, "adding elements failed");
}

/// remove int from list
unittest
{
    int[] arr = [1, 3];
    auto list = new List!int(arr);
    list.put(5);
    list.remove(1);
    assert(list[0] == 3 && list[1] == 5, "removing element failed");
}

/// remove int from list
unittest
{
    int[] arr = [1, 3];
    auto list = new List!int(arr);
    list.put(5);
    list.removeAt(1);
    assert(list[0] == 1 && list[1] == 5, "removing element failed");
}