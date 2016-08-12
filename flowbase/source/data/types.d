module flowbase.data.types;
import flowbase.data.interfaces;
import flowbase.data.signals;

import core.sync.mutex;

import flowbase.type.types;

/** describes the availability of the data
	Entity:		the data object is only available to the parts of the entity it was created in
	Device:		the data object can be synchronized to all data bags hosted on the device they are created/loaded
	Global:		the data object can be synchronized to all data bags hosted in the cloud/swarm
	Service: 	the data object is global available and can be processed by any data service in the whole cloud/swarm

	Independent of the availability of a data object it gets synced to the partners data bag conserving the availability when actively transmitted over a communication channel.
 */
enum DataScope
{
	Entity,
	Device,
	Global,
	Service
}

/// data bag holding and manging data objects
class DataBag : DataList!IDataObject
{
	// TODO implement a real lot of stuff (see spec)

	private static __gshared List!DataBag _bags;
	private static Mutex _bagsLock;

	private string _id;

	@property string id()
	{
		return this._id;
	}

	static this()
	{
		_bags = new List!DataBag();
		_bagsLock = new Mutex;
	}

	this(string id)
	{
		this._id = id;

		synchronized (_bagsLock)
			_bags.put(this);
	}

	~this()
	{
		synchronized (_bagsLock)
			_bags.remove(this);
	}
}

struct DataPropertyInfo
{
	TypeInfo typeInfo;
	bool isNullable;
}
