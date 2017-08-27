import std.stdio, std.bitmanip, std.encoding, std.array, std.algorithm.iteration, std.uuid, std.datetime, std.datetime.systime;

void main() {
	UUID uuid_test = randomUUID;
	writeln(uuid_test.data);

	SysTime systime_test = Clock.currTime;
	writeln(systime_test.toUnixTime.nativeToBigEndian);
	
	writeln(cast(ubyte[])"foo");

	//DateTime datetime_test;
	//writeln(datetime_test.toISOString.array.map!(c=>c.nativeToBigEndian).array.join);

	//Date date_test;
	//writeln(datetime_test.toISOString.array.map!(c=>c.nativeToBigEndian).array.join);

	Duration duration_test = dur!"hnsecs"(1);
	writeln(duration_test.total!"hnsecs".nativeToBigEndian);
}
