module flowbase.data.tests;
import flowbase.data.meta;
import flowbase.data.signals;
import flowbase.data.types;

version (unittest)
{
    import std.stdio;
    
    import flowbase.type.types;
}

version (unittest) mixin DataObjectPragmaMsg!("TestDataObject2", [DataProperty!(Ref!string, "propNString")]);

version (unittest) mixin DataObject!("TestDataObject2", [DataProperty!(Ref!string, "propNString")]);

version (unittest) mixin DataObjectPragmaMsg!("TestDataObject", [
    DataProperty!(Ref!int, "propNInt"),
    DataProperty!(string, "propString"),
    DataProperty!(TestDataObject2, "propDo2"),
    DataProperty!(DataList!double, "propListDouble")
    ]);

version (unittest) mixin DataObject!("TestDataObject", [
    DataProperty!(Ref!int, "propNInt"),
    DataProperty!(string, "propString"),
    DataProperty!(TestDataObject2, "propDo2"),
    DataProperty!(DataList!double, "propListDouble")
    ]);

// TODO unittests for DataList properties
// TODO unittests for data bag
// TODO unittests for TestDataObject propListDouble
// TODO unittests for thread safety
// TODO unittests for data reflection
// TODO unittest for events
// TODO think about whats untested and implement that unittests

version (unittest) class PropertyObserver
{
    bool hitGenericChanging = false;
    void propertyChanging_Cancel_Watch(Object sender, PropertyChangingSignalArgs args)
    {
        if (args.propertyName == "propNInt")
        {
            assert(args.oldValue is null, "old value of propNInt is not null as expected");
            assert(args.newValue !is null && (cast(Ref!int) args.newValue)
                .value == 2, "new value is not 2 as expected");

            args.cancel = true;
        }

        hitGenericChanging = true;
    }

    bool hitGenericChanged = false;
    void propertyChanged_Watch(Object sender, PropertyChangedSignalArgs args)
    {
        if (args.propertyName == "propString")
        {
            assert(args.oldValue !is null && (cast(Ref!string) args.oldValue)
                .value == string.init, "old value of propString is null or not init value");
            assert(args.newValue !is null && (cast(Ref!string) args.newValue)
                .value == "foo", "new value is not \"foo\" as expected");
        }

        hitGenericChanged = true;
    }

    bool hitIntChanging = false;
    void intNPropertyChanging_Watch(Object sender, TypedPropertyChangingSignalArgs!(Ref!int) args)
    {
        assert(args.oldValue is null, "old value of propNInt is not null as expected");
        assert(args.newValue !is null && args.newValue.value == 2, "new value is not 2 as expected");

        args.cancel = true;

        hitIntChanging = true;
    }

    bool hitIntChanged = false;
    void intNPropertyChanged_Watch(Object sender, TypedPropertyChangedSignalArgs!(Ref!int) args)
    {
        hitIntChanged = true;
    }

    bool hitStringChanging = false;
    void stringPropertyChanging_Watch(Object sender, TypedPropertyChangingSignalArgs!(string) args)
    {
        hitStringChanging = true;
    }

    bool hitStringChanged = false;
    void stringPropertyChanged_Watch(Object sender, TypedPropertyChangedSignalArgs!(string) args)
    {
        assert(args.oldValue == string.init, "old value of propNInt is not init value as expected");
        assert(args.newValue == "foo", "new value is not \"foo\" as expected");

        hitStringChanged = true;
    }
}

/// test property getter and setter of DataObject
unittest
{
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");

    auto dO2 = new TestDataObject2(dB, "test");
    dO2.propNString = new Ref!string("bar");

    dO.propNInt = new Ref!int(2);
    assert(dO.propNInt !is null && dO.propNInt.value == 2,
        "Ref!int property of data object wasn't set/get correctly");

    dO.propString = "foo";
    assert(dO.propString == "foo", "string property of data object wasn't set/get correctly");

    dO.propDo2 = dO2;
    assert(dO.propDo2 !is null && dO.propDo2.propNString !is null
        && dO.propDo2.propNString.value == "bar",
        "DataObject property of data object wasn't set/get correctly");

    writeln("MODULE data; UNITTEST <test property getter and setter of DataObject> [SUCCESS]");
}

/// test id of DataObject
unittest
{
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");
    assert(dO.id.toString != "00000000-0000-0000-0000-000000000000",
        "DataObject initialized with empty uuid");

    writeln("MODULE data; UNITTEST <test id of DataObject> [SUCCESS]");
}

// test initial availability of DataObject
unittest
{
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");
    assert(dO.availability == DataScope.Entity,
        "inital availability is not the private data scope");

    writeln("MODULE data; UNITTEST <test initial availability of DataObject> [SUCCESS]");
}

// test domain of DataObject
unittest
{
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");
    assert(dO.domain == "test", "domain of DataObject isn't as set");

    writeln("MODULE data; UNITTEST <test domain of DataObject> [SUCCESS]");
}

/// test property generic changing and changed signal
unittest
{
    auto pO = new PropertyObserver();
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");
    dO.propertyChanging.connect(&pO.propertyChanging_Cancel_Watch);
    dO.propertyChanged.connect(&pO.propertyChanged_Watch);

    pO.hitGenericChanging = false;
    pO.hitGenericChanged = false;
    dO.propNInt = new Ref!int(2);
    assert(pO.hitGenericChanging, "property changing signal wasn't trigerred");
    assert(!pO.hitGenericChanged,
        "property changed was triggered even a cancel happened on changing signal");
    assert(dO.propNInt is null, "property was changed even a cancel happened on changing signal");

    pO.hitGenericChanging = false;
    pO.hitGenericChanged = false;
    dO.propString = "foo";
    assert(pO.hitGenericChanging, "property changing signal wasn't trigerred");
    assert(
        pO.hitGenericChanged,
        "property changed wasn't triggered even there happened no cancel on changing signal");

    writeln("MODULE data; UNITTEST <test property generic changing and changed signal> [SUCCESS]");
}

/// test property typed changing and changed signal
unittest
{
    auto pO = new PropertyObserver();
    auto dB = new DataBag("test");
    auto dO = new TestDataObject(dB, "test");
    dO.propNIntChanging.connect(&pO.intNPropertyChanging_Watch);
    dO.propNIntChanged.connect(&pO.intNPropertyChanged_Watch);
    dO.propStringChanging.connect(&pO.stringPropertyChanging_Watch);
    dO.propStringChanged.connect(&pO.stringPropertyChanged_Watch);

    pO.hitIntChanging = false;
    pO.hitIntChanged = false;
    dO.propNInt = new Ref!int(2);
    assert(pO.hitIntChanging, "property changing signal wasn't trigerred");
    assert(!pO.hitIntChanged,
        "property changed was triggered even a cancel happened on changing signal");
    assert(dO.propNInt is null, "property was changed even a cancel happened on changing signal");

    pO.hitStringChanging = false;
    pO.hitStringChanged = false;
    dO.propString = "foo";
    assert(pO.hitStringChanging, "property changing signal wasn't trigerred");
    assert(
        pO.hitStringChanged,
        "property changed wasn't triggered even there happened no cancel on changing signal");

    writeln("MODULE data; UNITTEST <test property typed changing and changed signal> [SUCCESS]");
}

/// test id of DataBag
unittest
{
    auto dB = new DataBag("test");
    assert(dB.id == "test", "id of DataBag isn't as set");

    writeln("MODULE data; UNITTEST <test id of DataBag> [SUCCESS]");
}
