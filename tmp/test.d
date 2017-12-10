import std.stdio;

void main() {
	ulong ds = 1280;
	int rs = 64;
				
	writeln(ds%rs==0 ? ds : rs*((ds/rs)+1));
}
