// D import file generated from './msgpack/attribute.d'
module msgpack.attribute;
import std.typetuple;
import std.traits;
struct nonPacked
{
}
package enum isPackedField(alias field) = staticIndexOf!(nonPacked, __traits(getAttributes, field)) == -1 && !isSomeFunction!(typeof(field));
