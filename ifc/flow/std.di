// D import file generated from './flow/std.d'
module flow.std;
import flow.core.data;
import core.time;
import std.uuid;
class IdData : Data
{
	mixin data!();
	mixin field!(UUID, "id");
}
class Damage : Data
{
	mixin data!();
	mixin field!(string, "msg");
	mixin field!(Data, "recovery");
}
class NetMeta : Data
{
	mixin data!();
	mixin field!(string, "addr");
}
class CentralNetMeta : NetMeta
{
	mixin data!();
	mixin array!(string, "lookups");
}
class DecentralNetMeta : NetMeta
{
	mixin data!();
	mixin array!(NodeInfo, "nodes");
}
class NodeInfo : Data
{
	mixin data!();
	mixin field!(string, "addr");
}
class ProcessConfig : Data
{
	mixin data!();
	mixin field!(size_t, "worker");
	mixin field!(bool, "hark");
	mixin array!(NetMeta, "nets");
}
class TickInfo : IdData
{
	mixin data!();
	mixin field!(EntityPtr, "entity");
	mixin field!(string, "type");
	mixin field!(UUID, "group");
}
enum EntityAccess 
{
	Local,
	Global,
}
class Receptor : Data
{
	mixin data!();
	mixin field!(string, "signal");
	mixin field!(string, "tick");
}
enum EventType 
{
	OnCreated,
	OnTicking,
	OnFrozen,
	OnDisposed,
}
class Event : Data
{
	mixin data!();
	mixin field!(EventType, "type");
	mixin field!(string, "tick");
}
class EntityPtr : Data
{
	mixin data!();
	mixin field!(string, "id");
	mixin field!(string, "space");
}
class Signal : IdData
{
	mixin data!();
	mixin field!(UUID, "group");
	mixin field!(EntityPtr, "src");
}
class Unicast : Signal
{
	mixin data!();
	mixin field!(EntityPtr, "dst");
}
class Multicast : Signal
{
	mixin data!();
	mixin field!(string, "space");
}
class Anycast : Signal
{
	mixin data!();
	mixin field!(string, "space");
}
class Ping : Multicast
{
	mixin data!();
}
class UPing : Unicast
{
	mixin data!();
}
class Pong : Unicast
{
	mixin data!();
	mixin field!(EntityPtr, "ptr");
	mixin array!(string, "signals");
}
class WrappedSignal : Unicast
{
	mixin data!();
	mixin field!(Signal, "signal");
}
