module flowbase.type.signals;
import flowbase.type.meta;
import flowbase.type.types;

/// argument you get from a CollectionChangingSignal
class CollectionChangingSignalArgs(E) : CancelableSignalArgs
{
	mixin TCollectionSignalArgs!E;
}

/// argument you get from a CollectionChangedSignal
class CollectionChangedSignalArgs(E) : SignalArgs
{
	mixin TCollectionSignalArgs!E;
}

/// signal notifying when a collection is about to change; this signal is cancelable
class SCollectionChanging(E)
{
	mixin TSignal!(Object, CollectionChangingSignalArgs!E);
}

/// signal notifying when a collection changed
class SCollectionChanged(E)
{
	mixin TSignal!(Object, CollectionChangedSignalArgs!E);
}