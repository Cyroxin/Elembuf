module implem;

import std.stdio, buffer;

string data(size_t characters)
{
		char[] data;
		data.reserve(characters);
		data.length = characters;

		foreach(i; 0 .. characters)
			if ((i & 1) == 0)
				data[i] = '<';
			else
				data[i] = '>';

		return cast(string) data;						
}

enum runs = 100_000; // Keep runs at least this high for accurate results

// Construction timings can vary drastically due to changes in memory availabillity,
// thus runs should be kept at 100k runs so that averages are valid.

void main()
{
	import std.datetime.stopwatch;

	auto sbuffer = StaticBuffer!()();
	auto cbuffer = StaticCopyBuffer!()();

	// INFO:
	// The benchmark is for comparing different internal implementations.
	// The benchmark writes half a page worth of data (%runs) times by reusing the buffer.

	// To even out the differences, as staticbuffer is internally 1 element larger than copybuffer, 
	// staticbuffer.max is decremented by one in the benchmark.
	
	auto sw = StopWatch();

	sw.start;
	foreach(i; 0..runs)
		scope const _temp = StaticBuffer!()();
	sw.stop;

	const bufcon = sw.peek/runs;
	writeln("Bench [circlebuf construction + destr]:",bufcon);

	sw.reset;
	sw.start;

	sbuffer.fill(data((sbuffer.max-1)/2));
	foreach(i; 0..runs)
	{
		sbuffer.fill(data((sbuffer.max-1)/2));
		sbuffer = sbuffer[$/2..$]; // Consume half of the data
		sbuffer.fill("|");
		sbuffer = sbuffer[1..$];
	}
	sw.stop;

	const bufrun = sw.peek/runs;
	writeln("Bench [circlebuf runtime]:",bufrun);

	sw.reset;
	sw.start;
	foreach(i; 0..runs)
		const _temp = StaticCopyBuffer!()();
	sw.stop;

	const cbufcon = sw.peek/runs;
	writeln("Bench [copybuf construction + destr]:",cbufcon);

	sw.reset;
	sw.start;
	cbuffer.fill(data(cbuffer.max/2));
	foreach(i; 0..runs)
	{
		cbuffer.fill(data(cbuffer.max/2));
		cbuffer = cbuffer[$/2..$]; // Consume half of the data
		cbuffer.fill("|");
		cbuffer = cbuffer[1..$];
	}
	sw.stop;

	const cbufrun = sw.peek/runs;
	writeln("Bench [copybuf runtime]:",cbufrun);

	writeln("\nReuses needed: ",(bufcon-cbufcon)/(cbufrun-bufrun)); // To make usage worth it

	assert(sbuffer == cbuffer);

	readln;

	// PERSONAL NOTES:
	// Constructing the circular buffer takes a long time. 
	// Using a copy buffer is better when buffer reuse is not possible or the program lifetime is short.
	// Results can be found below. 

	/*

	Windows 10 - AMD A8-6410 - 4GB memory - LDC 5 consecutive runs of 100k runs.
	
	Bench [circlebuf construction + destr]:67 ╬╝s and 7 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 8 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 7 hnsecs
	Bench [copybuf runtime]:178 ╬╝s and 9 hnsecs

	Reuses needed: 5

	Bench [circlebuf construction + destr]:72 ╬╝s and 3 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 6 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 2 hnsecs
	Bench [copybuf runtime]:179 ╬╝s and 1 hnsec

	Reuses needed: 5

	Bench [circlebuf construction + destr]:64 ╬╝s and 6 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 7 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 1 hnsec
	Bench [copybuf runtime]:179 ╬╝s

	Reuses needed: 4

	Bench [circlebuf construction + destr]:72 ╬╝s and 3 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 8 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 3 hnsecs
	Bench [copybuf runtime]:178 ╬╝s and 4 hnsecs

	Reuses needed: 5

	Bench [circlebuf construction + destr]:65 ╬╝s and 6 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 7 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 4 hnsecs
	Bench [copybuf runtime]:178 ╬╝s and 8 hnsecs

	Reuses needed: 4
	*/

}


