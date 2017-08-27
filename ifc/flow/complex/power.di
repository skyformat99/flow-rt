// D import file generated from './flow/complex/power.d'
module flow.complex.power;
import flow.core.data;
import flow.core.util;
import flow.core.engine;
import flow.std;
class Relation : Data
{
	mixin data!();
	mixin field!(EntityPtr, "entity");
	mixin field!(size_t, "power");
}
class Actuality : Data
{
	mixin data!();
	mixin field!(size_t, "power");
	mixin array!(Relation, "relations");
}
class Act : Unicast
{
	mixin data!();
	mixin field!(size_t, "power");
}
class React : Tick
{
	override @property bool accept();
}
class Exist : Tick
{
	override void run();
}
SpaceMeta createPower(string id, size_t amount, string[string] params);
