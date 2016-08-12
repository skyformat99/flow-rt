module flowbase.type.meta;

import flowbase.type.types;

mixin template TSignal(T1...)
{
    import std.signals;
    mixin Signal!(T1);
}

mixin template TCollectionSignalArgs(E)
{
	private E[] _added;
	private E[] _removed;

	@property E[] added()
	{
		return this._added;
	}

	@property E[] removed()
	{
		return this._removed;
	}

	this(E[] added, E[] removed)
	{
		this._added = added;
		this._removed = removed;
	}
}

mixin template TInputRangeOfList(E)
{
    size_t _frontPtr;

    @property E front()
    {
        return this._arr[this._frontPtr];
    }

    @property bool empty()
    {
        return this._arr[this._frontPtr .. $].length == 0;
    }

    E moveFront()
    {
        return this.front;
    } // existing because of some performance optimization thing... for REFRACTORING

    void popFront()
    {
        this._frontPtr++;
    }

    int opApply(int delegate(E) fn)
    {
        int result = 0;
        foreach(elem; this._arr)
        {
            result = fn(elem);
            
            if(result) break;
        }
        
        return result;
    }

    int opApply(int delegate(size_t, E) fn)
    {
        int result = 0;
        foreach(i, elem; this._arr)
        {
            result = fn(i, elem);
            
            if(result) break;
        }
        
        return result;
    }
}

mixin template TForwardRangeOfList(E)
{
}

mixin template TBidirectionalRangeOfList(E)
{
    size_t _backPtr;

    @property E back()
    {
        return this._arr[this._arr.length - this._backPtr - 1];
    }

    E moveBack()
    {
        return this.back;
    } // existing because of some performance optimization thing... for REFRACTORING

    void popBack()
    {
        this._backPtr++;
    }
}

mixin template TRandomAccessFiniteOfList(E)
{
    @property IRandomAccessFinite!E save()
    {
        auto clone = new List!E();
        clone._arr = this._arr;

        return clone;
    }

    E opIndex(size_t idx)
    {
        return this._arr[idx];
    }

    E moveAt(size_t idx)
    {
        return this._arr[idx];
    }

    @property size_t length()
    {
        return this._arr.length;
    }

    alias opDollar = length;

    RandomAccessFinite!E opSlice(size_t start, size_t end)
    {        
        auto clone = new List!E();
        clone._arr = this._arr[start..end];

        return clone;
    }
}

mixin template TEnumerableOfList(E)
{
    E[] toArray()
    {
        return this._arr.dup;
    }
}

mixin template TOutputRangeOfList(E)
{
    void put(E elem)
    {
        E[] arr;
        arr ~= elem;

        auto changingArgs = new CollectionChangingSignalArgs!E(arr, null);
        this.collectionChanging.emit(this, changingArgs);

        if(!changingArgs.cancel)
        {
            this.putInternal(elem);

            auto changedArgs = new CollectionChangedSignalArgs!E(arr, null);
            this.collectionChanged.emit(this, changedArgs);
        }
    }
}
mixin template TCollectionOfList(E)
{
    void remove(E elem)
    {
        E[] arr;
        arr ~= elem;

        auto changingArgs = new CollectionChangingSignalArgs!E(null, arr);
        this.collectionChanging.emit(this, changingArgs);
        
        if(!changingArgs.cancel)
        {
            this.removeInternal(elem);
            
            auto changedArgs = new CollectionChangedSignalArgs!E(null, arr);
            this.collectionChanged.emit(this, changedArgs);
        }
    }

    void clear()
    {
        if(this._arr !is null)
            synchronized (this._lock)
                this._arr = null;
    }

    bool contains(E elem)
    {
        foreach (e; this._arr) // costs a lot with huge data
            if (elem == e)
                return true;

        return false;
    }
}

mixin template TList(E)
{
    static import std.algorithm.mutation;
    static import core.sync.mutex;

    private E[] _arr;
    private core.sync.mutex.Mutex _lock;

    this()
    {
        this._lock = new core.sync.mutex.Mutex;
    }

    this(E[] arr)
    {
        this._lock = new core.sync.mutex.Mutex;

        this.put(arr);
    }

    ~this()
    {
        this.clear();
    }

    private void putInternal(E elem)
    {
        synchronized (this._lock)
            this._arr ~= elem;
    }

    void put(E[] arr)
    {
        if(arr.length > 0)
        {
            auto changingArgs = new CollectionChangingSignalArgs!E(arr, null);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel)
            {
                foreach (elem; arr)
                    this.putInternal(elem);

                auto changedArgs = new CollectionChangedSignalArgs!E(arr, null);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    private void removeInternal(E elem)
    {
        auto idx = this.indexOf(elem);

        synchronized (this._lock)
            std.algorithm.mutation.remove(this._arr, idx);
    }

    void remove(E[] arr)
    {
        if(arr.length > 0)
        {
            auto changingArgs = new CollectionChangingSignalArgs!E(null, arr);
            this.collectionChanging.emit(this, changingArgs);
            
            if(!changingArgs.cancel)
            {
                foreach (elem; arr)
                    this.removeInternal(elem);

                auto changedArgs = new CollectionChangedSignalArgs!E(null, arr);
                this.collectionChanged.emit(this, changedArgs);
            }
        }
    }

    void removeAt(size_t idx)
    {
        synchronized (this._lock)            
            std.algorithm.mutation.remove(this._arr, idx);
    }

    size_t indexOf(E elem)
    {
        return this.indexOf(elem, 0); // costs a lot with huge data
    }

    size_t indexOf(E elem, size_t startIdx)
    {
        foreach(i, e; this._arr[startIdx..$]) // costs a lot with huge data
            if (e == elem)
                return i;

        throw new RangeError("element not found");
    }

    size_t indexOfReverse(E elem)
    {
        return this.indexOfReverse(elem, this._arr.length - 1); // costs a lot with huge data
    }

    size_t indexOfReverse(E elem, size_t startIdx)
    {
        foreach_reverse(i, e; this._arr[0..$-startIdx]) // costs a lot with huge data
            if (e == elem)
                return i;

        throw new RangeError("element not found");
    }

    private SCollectionChanging!E _collectionChanging = new SCollectionChanging!E();
    private SCollectionChanged!E _collectionChanged = new SCollectionChanged!E();

    @property SCollectionChanging!E collectionChanging()
    {
        return this._collectionChanging;
    }

    @property SCollectionChanged!E collectionChanged()
    {
        return this._collectionChanged;
    }
}