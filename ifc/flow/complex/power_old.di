// D import file generated from './flow/complex/power_old.d'
module flow.complex.power_old;
import flow.core.data;
import flow.core.util;
import flow.core.engine;
import flow.std;
class Relation : Data
{
	mixin data!();
	mixin field!(EntityPtr, "entity");
	mixin field!(double, "power");
}
class Actuality : Data
{
	mixin data!();
	mixin field!(double, "power");
	mixin array!(Relation, "relations");
}
class Act : Unicast
{
	mixin data!();
	mixin field!(double, "power");
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
