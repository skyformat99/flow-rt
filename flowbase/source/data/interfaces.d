module flowbase.data.interfaces;
import flowbase.data.types;
import flowbase.data.signals;

import std.uuid;

/// interface for data objects
interface IDataObject
{
	@property UUID id();

	@property string domain();

	@property DataScope availability();
	@property void availability(DataScope value);

	@property SPropertyChanging propertyChanging();
	@property SPropertyChanged propertyChanged();
}

interface ISignal
{
}