module flowbase.data.signals;
import flowbase.data.interfaces;
import flowbase.data.meta;

import std.uuid;
import std.traits;

import flowbase.type.interfaces;
import flowbase.type.types;
import flowbase.type.meta;

/// argument you get from a PropertyChangingSignal
class PropertyChangingSignalArgs : CancelableSignalArgs
{
	mixin TPropertySignalArgs;
}

/// argument you get from a PropertyChangedSignal
class PropertyChangedSignalArgs : SignalArgs
{
	mixin TPropertySignalArgs;
}

/// argument you get from a TypedPropertyChangingSignal
class TypedPropertyChangingSignalArgs(T) : CancelableSignalArgs if (is(T : IDataObject) || is(T : IDataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == string))
{
	mixin TTypedPropertySignalArgs!T;
}

/// argument you get from a TypedPropertyChangedSignal
class TypedPropertyChangedSignalArgs(T) : SignalArgs if (is(T : IDataObject) || is(T : IDataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == string))
{
	mixin TTypedPropertySignalArgs!T;
}

/// signal notifying when a property is about to change; this signal is cancelable
class SPropertyChanging
{
	mixin TSignal!(Object, PropertyChangingSignalArgs);
}

/// signal notifying when a property changed
class SPropertyChanged
{
	mixin TSignal!(Object, PropertyChangedSignalArgs);
}

/// signal notifying when a property is about to change; this signal is cancelable
class STypedPropertyChanging(T) if (is(T : IDataObject) || is(T : IDataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == string))
{
	mixin TSignal!(Object, TypedPropertyChangingSignalArgs!T);
}

/// signal notifying when a property changed
class STypedPropertyChanged(T) if (is(T : IDataObject) || is(T : IDataList!A,A) || is(T : Ref!A,A) || isScalarType!T || is(T == UUID) || is(T == string))
{
	mixin TSignal!(Object, TypedPropertyChangedSignalArgs!T);
}