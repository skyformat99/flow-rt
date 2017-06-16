module flow.flow.event;

import std.traits, std.uuid, std.datetime, std.range.primitives;
import flow.base.interfaces;

mixin template TEvent(T1...)
{
    import std.signals;
    mixin Signal!(T1);
}

class EventArgs
{
}

/// signal arguents allowing cancelation
class CancelableEventArgs : EventArgs
{
	bool cancel = false;
}

template TPropertyEventArgs()
{
	private string _propertyName;
	private TypeInfo _type;
	private Object _oldValue;
	private Object _newValue;

	@property string propertyName()
	{
		return this._propertyName;
	}

	@property TypeInfo type()
	{
		return this._type;
	}

	@property Object oldValue()
	{
		return this._oldValue;
	}

	@property Object newValue()
	{
		return this._newValue;
	}

	this(string propertyName, TypeInfo type, Object oldValue, Object newValue)
	{
		this._propertyName = propertyName;
		this._type = type;
		this._oldValue = oldValue;
		this._newValue = newValue;
	}
}

template TTypedPropertyEventArgs(T)
{
	private T _oldValue;
	private T _newValue;

	@property T oldValue()
	{
		return this._oldValue;
	}

	@property T newValue()
	{
		return this._newValue;
	}

	this(T oldValue, T newValue)
	{
		this._oldValue = oldValue;
		this._newValue = newValue;
	}
}

/// argument you get from a PropertyChangingSignal
class PropertyChangingEventArgs : CancelableEventArgs
{
	mixin TPropertyEventArgs;
}

/// argument you get from a PropertyChangedSignal
class PropertyChangedEventArgs : EventArgs
{
	mixin TPropertyEventArgs;
}

/// argument you get from a TypedPropertyChangingSignal
class TypedPropertyChangingEventArgs(T) : CancelableEventArgs if (is(T : Data) || is(T : DataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	mixin TTypedPropertyEventArgs!T;
}

/// argument you get from a TypedPropertyChangedSignal
class TypedPropertyChangedEventArgs(T) : EventArgs if (is(T : Data) || is(T : DataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	mixin TTypedPropertyEventArgs!T;
}

/// signal notifying when a property is about to change; this signal is cancelable
class EPropertyChanging
{
	mixin TEvent!(Object, PropertyChangingEventArgs);
}

/// signal notifying when a property changed
class EPropertyChanged
{
	mixin TEvent!(Object, PropertyChangedEventArgs);
}

/// signal notifying when a property is about to change; this signal is cancelable
class ETypedPropertyChanging(T) if (is(T : Data) || is(T : DataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	mixin TEvent!(Object, TypedPropertyChangingEventArgs!T);
}

/// signal notifying when a property changed
class ETypedPropertyChanged(T) if (is(T : Data) || is(T : DataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == SysTime) || is(T == DateTime) || (isArray!T && isScalarType!(ElementType!T)))
{
	mixin TEvent!(Object, TypedPropertyChangedEventArgs!T);
}

mixin template TCollectionEventArgs(E)
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

/// argument you get from a CollectionChangingSignal
class CollectionChangingEventArgs(E) : CancelableEventArgs
{
	mixin TCollectionEventArgs!E;
}

/// argument you get from a CollectionChangedSignal
class CollectionChangedEventArgs(E) : EventArgs
{
	mixin TCollectionEventArgs!E;
}

/// signal notifying when a collection is about to change; this signal is cancelable
class ECollectionChanging(E)
{
	mixin TEvent!(Object, CollectionChangingEventArgs!E);
}

/// signal notifying when a collection changed
class ECollectionChanged(E)
{
	mixin TEvent!(Object, CollectionChangedEventArgs!E);
}