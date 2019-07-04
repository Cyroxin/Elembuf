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

// Construction timings can vary drastically due to changes in memory availabillity.
// Using a high run count mitigates the variance as average construction can be calculated.

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

	sbuffer.fill(data((sbuffer.max-2)/2));
	foreach(i; 0..runs)
	{
		sbuffer.fill(data((sbuffer.max-2)/2));
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

	static assert(sbuffer.max - 2 == cbuffer.max);
	assert(sbuffer == cbuffer);



	readln;


	// PERSONAL NOTES:
	// General: Copy buffer is better when buffer reuse is not possible due to slow circlebuf construction.
	// AMD A8: Linux implementations were cpu bound on AMD A8. Win mem allocation is 7.5x slower than lin.
	// Results can be found below.

	/*

	Windows 10 - AMD A8-6410 - 4GB memory - LDC release, 5 consecutive runs of 100k runs.
	
	Bench [circlebuf construction + destr]:67 ╬╝s and 7 hnsecs
	Bench [circlebuf runtime]:168 ╬╝s and 8 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 7 hnsecs
	Bench [copybuf runtime]:178 ╬╝s and 9 hnsecs

	Reuses needed: 5

	Linux MX-18.3 (Glibc) - AMD A8-6410 - 4GB memory - DMD release -nobounds, 100k runs.

	Bench [circlebuf construction + destr]:18 μs and 6 hnsecs
	Bench [circlebuf runtime]:14 μs and 5 hnsecs
	Bench [copybuf construction + destr]:2 μs
	Bench [copybuf runtime]:26 μs and 3 hnsecs

	Reuses needed: 1

	Linux MX-18.3 (Posix) - AMD A8-6410 - 4GB memory - DMD release -nobounds, 100k runs.

	Bench [circlebuf construction + destr]:27 μs and 5 hnsecs
	Bench [circlebuf runtime]:14 μs and 5 hnsecs
	Bench [copybuf construction + destr]:2 μs
	Bench [copybuf runtime]:26 μs and 2 hnsecs

	Reuses needed: 2
	*/

}


