module __flow.type;

import core.exception, core.sync.rwmutex;
import std.traits, std.range.interfaces, std.range.primitives;
import std.algorithm, std.uuid, std.datetime;

import __flow.event, __flow.data, __flow.exception;

version(TODO) {
    // TODO implement
    class FiFo(T) : InputRange!T, OutputRange!T {
        @property size_t length();
        
        void put(T);
        void put(T[]);

        T pop();
        T[] pop(size_t amount);

        @property ECollectionChanging!T collectionChanging();
        @property ECollectionChanged!T collectionChanged();
        
    }

    // TODO implement
    class LiFo(T) : InputRange!T, OutputRange!T {
        void put(T);
        T pop();
        T pop(size_t amount);

        @property ECollectionChanging!T collectionChanging();
        @property ECollectionChanged!T collectionChanged();
    }
}

/** checks if type has a default (parameterless) constructor.
 * See_Also: http://dlang.org/spec/traits.html
 * Params: type to check
 * Returns: yes(true) or no[or unknown symbol](false)
 */
template hasDefaultConstructor(T) {
    enum hasDefaultConstructor = __traits(compiles, T()) || __traits(compiles, new T()); ///*__traits(compiles, T[0]) || */__traits(compiles, new T[0]);
}

/** checks if type has a specific constructor
 * See_Also: http://dlang.org/spec/traits.html
 * Params:
 *  T = type to check
 *  Args... = list of parameter to check for constructor
 */
template isConstructableWith(T, Args...) {
    enum isConstructableWith = __traits(compiles, T(Args.init)) || __traits(compiles, new T(Args.init));
}

/// generates code of list required by std.range.InputRange
mixin template TInputRangeOfList(T) {
    /** gets first element of list
     * See_Also: https://dlang.org/library/std/range/primitives/front.html
     * Returns: element
     */
    @property T front() {
        return this._arr.front;
    }

    /** checks if list is empty
     * See_Also: https://dlang.org/library/std/range/primitives/empty.html
     * Returns: yes(true) or no(false)
     */
    @property bool empty() {
        return this._arr.empty;
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_front.html
    T moveFront() {
        synchronized (this._lock.writer)
            return this._arr.moveFront();
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/pop_front.html
    void popFront() {
        synchronized (this._lock.writer)
            this._arr.popFront();
    }

    /// See_Also: https://dlang.org/spec/statement.html#ForeachTypeAttribute
    int opApply(scope int delegate(T) fn) {
        int result = 0;
        synchronized (this._lock.reader) foreach(e; this._arr) {
            result = fn(e);
            
            if(result) break;
        }
        
        return result;
    }

    /// See_Also: https://dlang.org/spec/statement.html#ForeachTypeAttribute
    int opApply(scope int delegate(size_t, T) fn) {
        int result = 0;
        synchronized (this._lock.reader) foreach(i, e; this._arr) {
            result = fn(i, e);
            
            if(result) break;
        }
        
        return result;
    }
}

/// generates code of list required by std.range.ForwardRange
mixin template TForwardRangeOfList(T) {
}

/// generates code of list required by std.range.BidirectionalRange
mixin template TBidirectionalRangeOfList(T) {
    size_t _backPtr;

    /** gets last element of list
    * See_Also: https://dlang.org/library/std/range/primitives/back.html
    * Returns: element
    */
    @property T back() {
        return this._arr.back;
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_back.html
    T moveBack() {
        synchronized (this._lock.writer)
            return this._arr.moveBack();
    } // existing because of some performance optimization thing... for REFRACTORING

    /// See_Also: https://dlang.org/library/std/range/primitives/pop_back.html
    void popBack() {
        synchronized (this._lock.writer)
            this._arr.popBack();
    }
}

/// generates code of list required by std.range.BidirectionalRange
mixin template TRandomAccessFiniteOfList(LT, T) {
    /// See_Also: https://dlang.org/library/std/range/primitives/save.html
    @property RandomAccessFinite!T save() {
        auto clone = new LT();
        synchronized (this._lock.reader) clone._arr = this._arr.save;

        return clone;
    }

    /** get element at specified index
     * See_Also: https://dlang.org/spec/operatoroverloading.html#array-ops
     * Params:
     *  size_t = index of element
     * Returns: element
     */
    T opIndex(size_t idx) {
        return this._arr[idx];
    }

    /// See_Also: https://dlang.org/library/std/range/primitives/move_at.html
    T moveAt(size_t idx) {
        synchronized (this._lock.writer)
            return this._arr.moveAt(idx);
    }

    /// See_Also: https://dlang.org/spec/operatoroverloading.html#array-ops
    alias opDollar = length;

    /// See_Also: https://dlang.org/spec/operatoroverloading.html#slice
    RandomAccessFinite!T opSlice(size_t start, size_t end) {
        synchronized (this._lock.reader) {
            auto clone = new LT();
            clone._arr = this._arr[start..end];

            return clone;
         }
    }
}

/// generates code of list required by std.range.OutputRange
mixin template TOutputRangeOfList(T) {
    /** puts an element at end of list
     * See_Also: https://dlang.org/library/std/range/primitives/put.html
     * Params:
     *  e = element to add
     */
    void put(T e) {
        this.put([e]);
    }
}

/// generates code of list required by __flow.type.ICollection
mixin template TCollectionOfList(T) {
    /** removes an element from collection if it is present
     * Params:
     *  e = element to remove
     */
    void remove(T e) {
        this.remove([e]);
    }

    /** clears whole collection */
    void clear() {
        T[] empty;
        synchronized (this._lock.writer)
            this._arr = empty;
    }

    /** Returns: length of collection */
    @property size_t length() {
        return this._arr.length;
    }

    /** checks if an element is present in collection
     * Params: element
     * Returns: yes(true) or no(false)
    */
    bool contains(T e) {
        synchronized (this._lock.reader)
            return this._arr.canFind(e);
    }
}

/// generates main code of list
mixin template TMainOfList(LT, T) {
    private T[] _arr;
    private ReadWriteMutex _lock;

    @property T[] array() {return this._arr.dup();}

    /// constructor taking an array of initial elements
    this(T[] arr) {
        this();

        this.put(arr);
    }

    /// constructor's preparing synchronization and event handling
    this() {
        this._lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        this._collectionChanging = new ECollectionChanging!T;
        this._collectionChanged = new ECollectionChanged!T;
    }
    
    void put(T[] arr) {
        if(arr.length > 0) {
            auto changingArgs = new CollectionChangingEventArgs!T(arr, null);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel) {
                synchronized (this._lock.writer)
                    this._arr ~= arr;

                auto changedArgs = new CollectionChangedEventArgs!T(arr, null);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    void put(LT l) {
        this.put(l._arr);
    }

    void remove(T[] arr) {
        if(arr.length > 0) {
            auto changingArgs = new CollectionChangingEventArgs!T(null, arr);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel) {
                static import std.algorithm.mutation;
                synchronized (this._lock.writer) {
                    foreach (e; arr)
                        this._arr = std.algorithm.mutation.remove(this._arr, this.indexOfInternal(e, 0)); // TODO can be optimized
                }

                auto changedArgs = new CollectionChangedEventArgs!T(null, arr);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    void removeAt(size_t idx) {
        static import std.algorithm.mutation;
        synchronized (this._lock.writer)
            this._arr = std.algorithm.mutation.remove(this._arr, idx);
    }

    size_t indexOf(T e) {
        return this.indexOf(e, 0); // costs a lot with huge data
    }

    size_t indexOf(T e, size_t startIdx) {
        synchronized (this._lock.reader)
            return this.indexOfInternal(e, startIdx);
    }
    
    private size_t indexOfInternal(T e, size_t startIdx) {
        foreach(i, e_; this._arr[startIdx..$]) // costs a lot with huge data
            static if(__traits(compiles, e_ is null)) {
                if ((e_ is null && e is null) || e_ == e)
                    return i;
            } else {
                if (e_ == e)
                    return i;
            }

        throw new RangeError("element not found");
    }

    size_t indexOfReverse(T e) {
        return this.indexOfReverse(e, this._arr.length - 1); // costs a lot with huge data
    }

    size_t indexOfReverse(T e, size_t startIdx) {
        synchronized (this._lock.reader)
            return this.indexOfReverseInternal(e, startIdx);
    }

    size_t indexOfReverseInternal(T e, size_t startIdx) {
        foreach_reverse(i, e_; this._arr[0..$-startIdx]) // costs a lot with huge data
            if (e_ == e)
                return i;

        throw new RangeError("element not found");
    }

    private ECollectionChanging!T _collectionChanging;
    private ECollectionChanged!T _collectionChanged;

    @property ECollectionChanging!T collectionChanging() {
        return this._collectionChanging;
    }

    @property ECollectionChanged!T collectionChanged() {
        return this._collectionChanged;
    }

    LT dup() {
        auto clone = new LT;
        clone._arr = this._arr.dup();

        return clone;
    }
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if ((isArray!T && isScalarType!(ElementType!T))) {
	T value;

	alias value this;

	this(T value) {
		this.value = value;
	}

    Ref!T dup() {
        return new Ref!T(this.value.dup);
    }
}

/// mask scalar, uuid and string types into nullable ptr types
class Ref(T) if (isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime)) {
	T value;

	alias value this;

	this(T value) {
		this.value = value;
	}

    Ref!T dup() {
        return new Ref!T(this.value);
    }
}

/** easy to use .NET oriented list of elements implementing notifications when collection changes
 *  write access and critical operations are synchronized
 * Bugs:
 *  - critical non writing operations are blocking each other (https://github.com/RalphBariz/flow-base/issues/2)
 */
class List(T) : RandomAccessFinite!T, OutputRange!T {
    mixin TInputRangeOfList!T;
    mixin TForwardRangeOfList!T;
    mixin TBidirectionalRangeOfList!T;
    mixin TRandomAccessFiniteOfList!(List!T, T);
    mixin TOutputRangeOfList!T;
    mixin TCollectionOfList!T;
    mixin TMainOfList!(List!T, T);
}

/** easy to use .NET oriented list of flow data elements implementing notifications when collection changes
 *  write and critical reading operations are synchronized
 * Bugs:
 *  - critical reading non writing operations are blocking each other
 */
class DataList(T) : RandomAccessFinite!T, OutputRange!T if (is(T : Data) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T))) {
    mixin TInputRangeOfList!T;
    mixin TForwardRangeOfList!T;
    mixin TBidirectionalRangeOfList!T;
    mixin TRandomAccessFiniteOfList!(DataList!T, T);
    mixin TOutputRangeOfList!T;
    mixin TCollectionOfList!T;
    mixin TMainOfList!(DataList!T, T);
}

class InvalidStateException : FlowException {
    mixin TException;
}

class StateMachine(T) if (isScalarType!T) {
    import core.sync.rwmutex;

    import __flow.exception;

    private ReadWriteMutex _lock;
    private T _state;

    protected @property ReadWriteMutex lock() {return this._lock;}

    @property T state() {
        synchronized(this._lock.reader) return this._state;
    }

    protected @property void state(T value) {
        auto allowed = false;
        T oldState;
        synchronized(this._lock.writer) {
            if(this._state != value) {
                allowed = this.onStateChanging(this._state, value);

                if(allowed) {
                    oldState = this._state;
                    this._state = value;
                }
            }
        }
        
        if(allowed)
            this.onStateChanged(oldState, this._state);
    }

    protected this() {
        this._lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    protected void ensureState(T requiredState) {
        if(this.state != requiredState)
            throw new InvalidStateException();
    }

    protected void ensureStateOr(T[] possibleStates) {
        synchronized(this._lock.reader) {
            auto found = false;
            foreach(ps; possibleStates)
                if(ps == this._state) {
                    found = true;
                    break;
                }
            if(!found)
                throw new InvalidStateException();
        }
    }

    protected bool onStateChanging(T oldState, T newState) {return true;}
    protected void onStateChanged(T oldState, T newState) {}
}
unittest{/*TODO*/}

/// Returns: full qualified name of type
template fqn(T) {
    enum fqn = fullyQualifiedName!T;
}

/// enables a type to be aware of its fully qualified name
interface __IFqn {
    public @property string __fqn();
}

/// gets the fully qualified name of an element's type implementing __IFqn
string fqnOf(__IFqn x) {
    return x.__fqn;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}