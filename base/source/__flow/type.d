module __flow.type;

import core.exception;
import std.traits, std.range.interfaces, std.range.primitives, std.uuid, std.datetime;

import __flow.event;
import flow.base.interfaces;

/// interfaces collection of elements
interface ICollection(E) : RandomAccessFinite!E, OutputRange!E
{
    /** removes an element from collection if it is present
     * Params:
     *  E = element to remove
     */
    void remove(E);

    /** clears whole collection */
    void clear();

    /** Returns: length of collection */
    @property size_t length();

    /** checks if an element is present in collection
     * Params: element
     * Returns: yes(true) or no(false)
    */
    bool contains(E);

    /** event beeing triggered when collection is about to change.
        event is cancellable see __flow.event.CancelableEventArgs.
     * Returns: event with args __flow.event.CollectionChangingEventArgs
     */
    @property ECollectionChanging!E collectionChanging();

    /** event beeing triggered when collection is about to change.
     * Returns: event with args __flow.event.CollectionChangedEventArgs
     */
    @property ECollectionChanged!E collectionChanged();
}

/// interfaces list of elements
interface IList(E) : ICollection!E
{
    /** puts an element at end of list
     * See_Also: https://dlang.org/library/std/range/primitives/put.html
     * Params:
     *  E = element to add
     */
    void put(E);    // had to repeat due to overloading only works local

    /** puts multiple elements at end of list    
     * Params:
     *  E = array of elements to add
     */
    void put(E[]);

    /** removes an element from list    
     * Params:
     *  E = element to remove
     */
    void remove(E); // had to repeat due to overloading only works local

    /** removes multiple elements from list    
     * Params:
     *  E = array of elements to remove
     */
    void remove(E[]);

    /** removes an element at a specific index from list    
     * Params:
     *  size_t = index to remove
     */
    void removeAt(size_t);

    /** gets first index of a specific element
     * Prams:
     *  E = element for getting its index
     * Returns: index
    */
    size_t indexOf(E);

    /** gets next index of a specific element
     * Prams:
     *  E = element for getting its index
     *  size_t = index to start +1 (usually index of last finding + 1)
     * Returns: index
    */
    size_t indexOf(E, size_t);

    /** gets last index of a specific element
     *  this function does a backsearch 
     * Prams:
     *  E = element for getting its index
     * Returns: index
     */
    size_t indexOfReverse(E);

    /** gets last index of a specific element
     *  this function does a backsearch 
     * Prams:
     *  E = element for getting its index
     *  size_t = index to start -1 (usually index of last finding - 1)
     * Returns: index
     */
    size_t indexOfReverse(E, size_t);

    /** get element at specified index
     * See_Also: https://dlang.org/spec/operatoroverloading.html#array-ops
     * Params:
     *  size_t = index of element
     * Returns: element
     */
    E opIndex(size_t);

    /// Returns: duplicate of the list
    IList!E dup();
}

/** list allowing only flow compatible data types.
 *  if you want to transport collections of data inside flow, this descripes what you need
 */
interface DataList(T) : IList!T if (is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
}

version(TODO) {
    // TODO implement
    interface IFiFo(E) : InputRange!E, OutputRange!E
    {
        @property size_t length();
        
        void put(E);
        void put(E[]);

        E pop();
        E[] pop(size_t amount);

        @property ECollectionChanging!E collectionChanging();
        @property ECollectionChanged!E collectionChanged();
        
    }

    // TODO implement
    interface ILiFo(E) : InputRange!E, OutputRange!E
    {
        void put(E);
        E pop();
        E pop(size_t amount);

        @property ECollectionChanging!E collectionChanging();
        @property ECollectionChanged!E collectionChanged();
    }
}

/** checks if type has a default (parameterless) constructor.
 * See_Also: http://dlang.org/spec/traits.html
 * Params: type to check
 * Returns: yes(true) or no[or unknown symbol](false)
 */
template hasDefaultConstructor(T)
{
    enum hasDefaultConstructor = __traits(compiles, T()) || __traits(compiles, new T()); ///*__traits(compiles, T[0]) || */__traits(compiles, new T[0]);
}

/** checks if type has a specific constructor
 * See_Also: http://dlang.org/spec/traits.html
 * Params:
 *  T = type to check
 *  Args... = list of parameter to check for constructor
 */
template isConstructableWith(T, Args...)
{
    enum isConstructableWith = __traits(compiles, T(Args.init)) || __traits(compiles, new T(Args.init));
}

/// generates code of list required by std.range.InputRange
mixin template TInputRangeOfList(E)
{
    /** gets first element of list
     * See_Also: https://dlang.org/library/std/range/primitives/front.html
     * Returns: element
     */
    @property E front()
    {
        return this._arr.front;
    }

    /** checks if list is empty
     * See_Also: https://dlang.org/library/std/range/primitives/empty.html
     * Returns: yes(true) or no(false)
     */
    @property bool empty()
    {
        return this._arr.empty;
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_front.html
    E moveFront()
    {
        synchronized (this._lock.writer)
            return this._arr.moveFront();
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/pop_front.html
    void popFront()
    {
        synchronized (this._lock.writer)
            this._arr.popFront();
    }

    /// See_Also: https://dlang.org/spec/statement.html#ForeachTypeAttribute
    int opApply(scope int delegate(E) fn)
    {
        int result = 0;
        synchronized (this._lock.reader) foreach(e; this._arr)
        {
            result = fn(e);
            
            if(result) break;
        }
        
        return result;
    }

    /// See_Also: https://dlang.org/spec/statement.html#ForeachTypeAttribute
    int opApply(scope int delegate(size_t, E) fn)
    {
        int result = 0;
        synchronized (this._lock.reader) foreach(i, e; this._arr)
        {
            result = fn(i, e);
            
            if(result) break;
        }
        
        return result;
    }
}

/// generates code of list required by std.range.ForwardRange
mixin template TForwardRangeOfList(E)
{
}

/// generates code of list required by std.range.BidirectionalRange
mixin template TBidirectionalRangeOfList(E)
{
    size_t _backPtr;

    /** gets last element of list
    * See_Also: https://dlang.org/library/std/range/primitives/back.html
    * Returns: element
    */
    @property E back()
    {
        return this._arr.back;
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_back.html
    E moveBack()
    {
        synchronized (this._lock.writer)
            return this._arr.moveBack();
    } // existing because of some performance optimization thing... for REFRACTORING

    /// See_Also: https://dlang.org/library/std/range/primitives/pop_back.html
    void popBack()
    {
        synchronized (this._lock.writer)
            this._arr.popBack();
    }
}

/// generates code of list required by std.range.BidirectionalRange
mixin template TRandomAccessFiniteOfList(T, E)
{
    /// See_Also: https://dlang.org/library/std/range/primitives/save.html
    @property RandomAccessFinite!E save()
    {
        auto clone = new T();
        synchronized (this._lock.reader) clone._arr = this._arr.save;

        return clone;
    }

    /** get element at specified index
     * See_Also: https://dlang.org/spec/operatoroverloading.html#array-ops
     * Params:
     *  size_t = index of element
     * Returns: element
     */
    E opIndex(size_t idx)
    {
        return this._arr[idx];
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_at.html
    E moveAt(size_t idx)
    {
        synchronized (this._lock.writer)
            return this._arr.moveAt(idx);
    }

    /// See_Also: https://dlang.org/spec/operatoroverloading.html#array-ops
    alias opDollar = length;

    /// See_Also: https://dlang.org/spec/operatoroverloading.html#slice
    RandomAccessFinite!E opSlice(size_t start, size_t end)
    {        
        synchronized (this._lock.reader)
        {
            auto clone = new T();
            clone._arr = this._arr[start..end];

            return clone;
         }
    }
}

/// generates code of list required by std.range.OutputRange
mixin template TOutputRangeOfList(E)
{
    /** puts an element at end of list
     * See_Also: https://dlang.org/library/std/range/primitives/put.html
     * Params:
     *  E = element to add
     */
    void put(E e)
    {
        this.put([e]);
    }
}

/// generates code of list required by __flow.type.ICollection
mixin template TCollectionOfList(E)
{
    /** removes an element from collection if it is present
     * Params:
     *  E = element to remove
     */
    void remove(E e)
    {
        this.remove([e]);
    }

    /** clears whole collection */
    void clear()
    {
        synchronized (this._lock.writer)
            this._arr = null;
    }

    /** Returns: length of collection */
    @property size_t length()
    {
        return this._arr.length;
    }

    /** checks if an element is present in collection
     * Params: element
     * Returns: yes(true) or no(false)
    */
    bool contains(E e)
    {
        synchronized (this._lock.reader)
            foreach (e_; this._arr)
                if (e_ == e)
                    return true;

        return false;
    }
}

/// generates main code of list
mixin template TMainOfList(E)
{
    static import core.sync.rwmutex;

    private E[] _arr;
    private core.sync.rwmutex.ReadWriteMutex _lock;

    /// constructor taking an array of initial elements
    this(E[] arr)
    {
        this();

        this.put(arr);
    }

    /// constructor's preparing synchronization and event handling
    this()
    {
        this._lock = new core.sync.rwmutex.ReadWriteMutex(core.sync.rwmutex.ReadWriteMutex.Policy.PREFER_WRITERS);
        this._collectionChanging = new ECollectionChanging!E;
        this._collectionChanged = new ECollectionChanged!E;
    }
    
    void put(E[] arr)
    {
        if(arr.length > 0)
        {
            auto changingArgs = new CollectionChangingEventArgs!E(arr, null);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel)
            {
                synchronized (this._lock.writer)
                    this._arr = this._arr ~= arr;

                auto changedArgs = new CollectionChangedEventArgs!E(arr, null);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    void remove(E[] arr)
    {
        if(arr.length > 0)
        {
            auto changingArgs = new CollectionChangingEventArgs!E(null, arr);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel)
            {
                static import std.algorithm.mutation;
                synchronized (this._lock.writer)
                {
                    foreach (e; arr)
                        this._arr = std.algorithm.mutation.remove(this._arr, this.indexOfInternal(e, 0)); // TODO can be optimized
                }

                auto changedArgs = new CollectionChangedEventArgs!E(null, arr);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    void removeAt(size_t idx)
    {
        static import std.algorithm.mutation;
        synchronized (this._lock.writer)
            this._arr = std.algorithm.mutation.remove(this._arr, idx);
    }

    size_t indexOf(E e)
    {
        return this.indexOf(e, 0); // costs a lot with huge data
    }

    size_t indexOf(E e, size_t startIdx)
    {
        synchronized (this._lock.reader)
            return this.indexOfInternal(e, startIdx);
    }
    
    private size_t indexOfInternal(E e, size_t startIdx)
    {
        foreach(i, e_; this._arr[startIdx..$]) // costs a lot with huge data
            static if(__traits(compiles, e_ is null))
            {
                if ((e_ is null && e is null) || e_ == e)
                    return i;
            }
            else
            {
                if (e_ == e)
                    return i;
            }

        throw new RangeError("element not found");
    }

    size_t indexOfReverse(E e)
    {
        return this.indexOfReverse(e, this._arr.length - 1); // costs a lot with huge data
    }

    size_t indexOfReverse(E e, size_t startIdx)
    {
        synchronized (this._lock.reader)
            return this.indexOfReverseInternal(e, startIdx);
    }

    size_t indexOfReverseInternal(E e, size_t startIdx)
    {
        foreach_reverse(i, e_; this._arr[0..$-startIdx]) // costs a lot with huge data
            if (e_ == e)
                return i;

        throw new RangeError("element not found");
    }

    private ECollectionChanging!E _collectionChanging;
    private ECollectionChanged!E _collectionChanged;

    @property ECollectionChanging!E collectionChanging()
    {
        return this._collectionChanging;
    }

    @property ECollectionChanged!E collectionChanged()
    {
        return this._collectionChanged;
    }
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if ((isArray!T && isScalarType!(ElementType!T)))
{
	T value;

	alias value this;

	this(T value)
	{
		this.value = value;
	}

    Ref!T dup()
    {
        return new Ref!T(this.value.dup);
    }
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if (isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime))
{
	T value;

	alias value this;

	this(T value)
	{
		this.value = value;
	}

    Ref!T dup()
    {
        return new Ref!T(this.value);
    }
}

/** easy to use .NET oriented list of elements implementing notifications when collection changes
 *  write access and critical operations are synchronized
 * Bugs:
 *  - critical non writing operations are blocking each other (https://github.com/RalphBariz/flow-base/issues/2)
 */
class List(E) : IList!E
{
    mixin TInputRangeOfList!E;
    mixin TForwardRangeOfList!E;
    mixin TBidirectionalRangeOfList!E;
    mixin TRandomAccessFiniteOfList!(List!E, E);
    mixin TOutputRangeOfList!E;
    mixin TCollectionOfList!E;
    mixin TMainOfList!E;

    List!E dup()
    {
        List!E clone = new List!E(this._arr.dup);

        return clone;
    }
}

/** easy to use .NET oriented list of flow data elements implementing notifications when collection changes
 *  write and critical reading operations are synchronized
 * Bugs:
 *  - critical reading non writing operations are blocking each other
 */
class DataList(E) : DataList!E
{
    mixin TInputRangeOfList!E;
    mixin TForwardRangeOfList!E;
    mixin TBidirectionalRangeOfList!E;
    mixin TRandomAccessFiniteOfList!(DataList!E, E);
    mixin TOutputRangeOfList!E;
    mixin TCollectionOfList!E;
    mixin TMainOfList!E;

    DataList!E dup()
    {
        DataList!E clone = new DataList!E(this._arr.dup);

        return clone;
    }
}

/// a put extension for collections to support ducktyping
OutputRange!T dPut(T)(OutputRange!T range, T e)
{
    range.put(e);
    return range;
}
unittest{/*TODO*/}

/// a remove extension for collections to support ducktyping
ICollection!T dRemove(T)(ICollection!T collection, T e)
{
    collection.remove(e);
    return collection;
}
unittest{/*TODO*/}

/// Returns: full qualified name of type
template fqn(T)
{
    enum fqn = fullyQualifiedName!T;
}

/// enables a type to be aware of its fully qualified name
interface __IFqn
{
    @property string __fqn();
}

/// gets the fully qualified name of an element's type implementing __IFqn
string fqnOf(__IFqn x)
{
    return x.__fqn;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}