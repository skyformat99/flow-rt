void main () {
	import std.stdio, std.conv;
	immutable uint size=2^^16;
	writeln("size: " ~ size.to!string);
	uint[size] a = void;
	writeln(a);
}
