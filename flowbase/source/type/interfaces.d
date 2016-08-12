module flowbase.type.interfaces;
import flowbase.type.signals;

import std.range.interfaces;
import std.traits;

import flowbase.data.interfaces;

interface IInputRange(E) : InputRange!E
{    
}

interface IForwardRange(E) : ForwardRange!E
{    
}

interface IBidirectionalRange(E) : BidirectionalRange!E
{    
}

interface IRandomAccessFinite(E) : RandomAccessFinite!E
{
}

interface IOutputRange(E) : OutputRange!E
{
}

interface IEnumerable(E) : IRandomAccessFinite!E
{
    E[] toArray();
}

interface ICollection(E) : IEnumerable!E, IOutputRange!E
{
    void remove(E);
    void clear();
    bool contains(E);

    @property SCollectionChanging!E collectionChanging();
    @property SCollectionChanged!E collectionChanged();
}

interface IList(E) : ICollection!E
{
    void put(E);    // have to repeat due to overloading only working local
    void put(E[]);
    void remove(E); // have to repeat due to overloading only working local
    void remove(E[]);

    void removeAt(size_t);

    size_t indexOf(E);
    size_t indexOf(E, size_t);
    size_t indexOfReverse(E);
    size_t indexOfReverse(E, size_t);

    E opIndex(size_t);
}

interface IReadonlyList(E) : IEnumerable!E
{
    size_t indexOf(E);
    size_t indexOf(E, size_t);
    size_t indexOfReverse(E);
    size_t indexOfReverse(E, size_t);

    E opIndex(size_t);
}

interface IDataList(E) : IList!E if (is(E : IDataObject) || isScalarType!E
        || is(E == UUID) || is(E == string))
{
}

// TODO implement
interface IFiFo(E)
{
    @property size_t length();
    
    void put(E);
    void put(E[]);

    E pop();
    E[] pop(size_t amount);

    @property SCollectionChanging!E collectionChanging();
    @property SCollectionChanged!E collectionChanged();
    
}

// TODO implement
interface ILiFo(E)
{
    void put(E);
    E pop();
    E pop(size_t amount);

    @property SCollectionChanging!E collectionChanging();
    @property SCollectionChanged!E collectionChanged();
}
