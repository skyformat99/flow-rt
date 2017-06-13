module flow.test.data;
import flow.flow.data;

import std.uuid;

import flow.flow.event, flow.flow.type;


// TODO unittests for DataList properties
// TODO unittests for data bag
// TODO unittests for TestData propListDouble
// TODO unittests for thread safety
// TODO unittests for data reflection
// TODO unittest for events
// TODO think about whats untested and implement that unittests

version (unittest)
{    
    class TestRecursiveData : Data
    {
        mixin TData;
        mixin TField!(TestRecursiveData, "propRecursive");
        mixin TList!(TestRecursiveData, "propNRecursive");
    }

    class TestData2 : Data
    {
        mixin TData;
        mixin TField!(string, "propString");
    }

    class TestData : Data
    {
        mixin TData;
        mixin TField!(int, "propInt");
        mixin TField!(string, "propString");
        mixin TField!(double, "propDouble");
        mixin TField!(TestData2, "propDo2");
        mixin TList!(double, "propListDouble");
    }

    class PropertyObserver
    {
        bool hitGenericChanging = false;
        void propertyChanging_Cancel_Watch(Object sender, PropertyChangingEventArgs args)
        {
            if (args.propertyName == "propInt")
            {
                assert(args.oldValue !is null &&  args.oldValue.as!(Ref!int)
                    .value == int.init, "old value of propInt is not null as expected");
                assert(args.newValue !is null && args.newValue.as!(Ref!int)
                    .value == 2, "new value is not 2 as expected");

                args.cancel = true;
            }

            hitGenericChanging = true;
        }

        bool hitGenericChanged = false;
        void propertyChanged_Watch(Object sender, PropertyChangedEventArgs args)
        {
            if (args.propertyName == "propString")
            {
                assert(args.oldValue !is null && args.oldValue.as!(Ref!string)
                    .value == string.init, "old value of propString is null or not init value");
                assert(args.newValue !is null && args.newValue.as!(Ref!string)
                    .value == "foo", "new value is not \"foo\" as expected");
            }

            hitGenericChanged = true;
        }

        bool hitIntChanging = false;
        void intPropertyChanging_Watch(Object sender, TypedPropertyChangingEventArgs!(int) args)
        {
            assert(args.oldValue == int.init, "old value of proInt is not null as expected");
            assert(args.newValue == 2, "new value is not 2 as expected");

            args.cancel = true;

            hitIntChanging = true;
        }

        bool hitIntChanged = false;
        void intPropertyChanged_Watch(Object sender, TypedPropertyChangedEventArgs!(int) args)
        {
            hitIntChanged = true;
        }

        bool hitStringChanging = false;
        void stringPropertyChanging_Watch(Object sender, TypedPropertyChangingEventArgs!(string) args)
        {
            hitStringChanging = true;
        }

        bool hitStringChanged = false;
        void stringPropertyChanged_Watch(Object sender, TypedPropertyChangedEventArgs!(string) args)
        {
            assert(args.oldValue == null, "old value of propString is not null as expected");
            assert(args.newValue == "foo", "new value is not \"foo\" as expected");

            hitStringChanged = true;
        }
    }
}

/// test property getter and setter of Data
unittest
{
    auto dO = new TestData;

    auto dO2 = new TestData2;
    dO2.propString = "bar";

    dO.propInt = 2;
    assert(dO.propInt == 2,
        "int property of data object wasn't set/get correctly");

    dO.propString = "foo";
    assert(dO.propString == "foo", "string property of data object wasn't set/get correctly");

    dO.propDo2 = dO2;
    assert(dO.propDo2 !is null && dO.propDo2.propString !is null
        && dO.propDo2.propString == "bar",
        "Data property of data object wasn't set/get correctly");
}

/// test property generic changing and changed signal
unittest
{
    auto pO = new PropertyObserver;
    auto dO = new TestData;
    dO.propertyChanging.connect(&pO.propertyChanging_Cancel_Watch);
    dO.propertyChanged.connect(&pO.propertyChanged_Watch);

    pO.hitGenericChanging = false;
    pO.hitGenericChanged = false;
    dO.propInt = 2;
    assert(pO.hitGenericChanging, "property changing signal wasn't trigerred");
    assert(!pO.hitGenericChanged,
        "property changed was triggered even a cancel happened on changing signal");
    assert(dO.propInt == int.init, "property was changed even a cancel happened on changing signal");

    pO.hitGenericChanging = false;
    pO.hitGenericChanged = false;
    dO.propString = "foo";
    assert(pO.hitGenericChanging, "property changing signal wasn't trigerred");
    assert(
        pO.hitGenericChanged,
        "property changed wasn't triggered even there happened no cancel on changing signal");
}

/// test property typed changing and changed signal
unittest
{
    auto pO = new PropertyObserver;
    auto dO = new TestData;
    dO.propIntChanging.connect(&pO.intPropertyChanging_Watch);
    dO.propIntChanged.connect(&pO.intPropertyChanged_Watch);
    dO.propStringChanging.connect(&pO.stringPropertyChanging_Watch);
    dO.propStringChanged.connect(&pO.stringPropertyChanged_Watch);

    pO.hitIntChanging = false;
    pO.hitIntChanged = false;
    dO.propInt = 2;
    assert(pO.hitIntChanging, "property changing signal wasn't trigerred");
    assert(!pO.hitIntChanged,
        "property changed was triggered even a cancel happened on changing signal");
    assert(dO.propInt == int.init, "property was changed even a cancel happened on changing signal");

    pO.hitStringChanging = false;
    pO.hitStringChanged = false;
    dO.propString = "foo";
    assert(pO.hitStringChanging, "property changing signal wasn't trigerred");
    assert(
        pO.hitStringChanged,
        "property changed wasn't triggered even there happened no cancel on changing signal");
}

/// test type id generation of data object
unittest
{
    import std.traits;
    
    auto dO = new TestData;
    assert(dO.dataType == fullyQualifiedName!TestData, "dataType of data object is generated wrong");
}

/// test duck set property
unittest
{
    auto dO = (new TestData)
        .set("propInt", 2)
        .set("propDouble", 2.0)
        .as!TestData;

    assert(dO.propInt == 2, "duck setting of propInt gone wrong");
    assert(dO.propDouble == 2.0, "duck setting of propDouble gone wrong");
}

version (unittest)
{
    class CloningTestData : Data
    {
        mixin TData;
        mixin TField!(UUID, "propId");
        mixin TField!(int, "propInt");
        mixin TField!(string, "propString");
        mixin TField!(TestData, "propTestData");
        mixin TField!(string, "propStringNull");
        mixin TField!(TestData, "propTestDataNull");
    }
}

/// test deep data cloning
unittest
{
    auto dO1 = (new CloningTestData)
        .set("propId", randomUUID)
        .set("propInt", 3)
        .set("propString", "foo")
        .set("propTestData", new TestData)
        .as!CloningTestData;
    
    auto dO2 = dO1.dup;

    assert(&dO1.propId != &dO2.propId && dO1.propId == dO2.propId, "cloning \"propId\" went wrong");
    assert(&dO1.propInt != &dO2.propInt && dO1.propInt == dO2.propInt, "cloning \"propInt\" went wrong");
    assert(&dO1.propString != &dO2.propString && dO1.propString == dO2.propString, "cloning \"propString\" went wrong");
    
    assert(&dO1.propTestData != &dO2.propTestData, "cloning \"propTestData\" went wrong");

    assert(dO2.propStringNull is null, "cloning null \"propStringNull\" went wrong");
    assert(dO2.propTestDataNull is null, "cloning null \"propTestDataNull\" went wrong");
}

version (unittest)
{
    class JsonTestData : Data
    {
        mixin TData;
        mixin TField!(UUID, "propId");
        mixin TField!(int, "propInt");
        mixin TField!(int[], "propIntA");
        mixin TField!(string, "propString");
        mixin TField!(TestData, "propTestData");
        mixin TField!(string, "propStringNull");
        mixin TField!(TestData, "propTestDataNull");
        mixin TList!(int[], "intAL");
        mixin TList!(TestData, "testDataL");
        mixin TList!(string, "stringL");
        mixin TList!(UUID, "uuidL");
    }
}

/// test Json generation
unittest
{
    auto id = randomUUID;
    auto dO1 = (new JsonTestData)
        .set("propId", id)
        .set("propInt", 3)
        .set("propIntA", [1,3,5,7,9])
        .set("propString", "foo")
        .set("propTestData", (new TestData).set("propDouble", 1.1).as!TestData)
        .as!JsonTestData;

    dO1.intAL.put([1,2,3]);
    dO1.intAL.put([4,5,6]);
    dO1.intAL.put([7,8,9]);

    dO1.testDataL.put((new TestData).set("propDouble", 2.1).as!TestData);
    dO1.testDataL.put((new TestData).set("propDouble", 2.2).as!TestData);
    dO1.testDataL.put((new TestData).set("propDouble", 2.3).as!TestData);

    dO1.stringL.put("alle");
    dO1.stringL.put("meine");
    dO1.stringL.put("entchen");

    auto id1 = randomUUID; auto id2 = randomUUID; auto id3 = randomUUID;
    dO1.uuidL.put(id1);
    dO1.uuidL.put(id2);
    dO1.uuidL.put(id3);
    
    auto json = dO1.toJson;

    auto dO2 = JsonTestData.fromJson(json);
    assert(dO2.propId == id);
    assert(dO2.propInt == 3);
    assert(dO2.propString == "foo");
    assert(dO2.propTestData.propDouble == 1.1);
    assert(dO2.propIntA == [1,3,5,7,9]);
    assert(dO2.intAL.length == 3);
    assert(dO2.intAL[0] == [1,2,3] && dO2.intAL[1] == [4,5,6] && dO2.intAL[2] == [7,8,9]);
    assert(dO2.testDataL.length == 3);
    assert(dO2.testDataL[0].propDouble == 2.1 && dO2.testDataL[1].propDouble == 2.2 && dO2.testDataL[2].propDouble == 2.3);
    assert(dO2.stringL.length == 3);
    assert(dO2.stringL[0] == "alle" && dO2.stringL[1] == "meine" && dO2.stringL[2] == "entchen");
    assert(dO2.uuidL.length == 3);
    assert(dO2.uuidL[0] == id1 && dO2.uuidL[1] == id2 && dO2.uuidL[2] == id3);
}
