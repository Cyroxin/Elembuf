module implem;

import std.stdio, elembuf;

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

void implemmain()
{
	import std.datetime.stopwatch;

	auto sbuffer = buffer("");
	auto cbuffer = StaticCopyBuffer!()();

	static assert(sbuffer.max -2 == cbuffer.max); // We will account for this in fills

	// INFO:
	// The benchmark is for comparing different internal implementations.
	// The benchmark writes half a page worth of data (%runs) times by reusing the buffer.
	// Amount of reuses indicates how many fills needs to be done to make using circularbuffer worth it.

	// Buffer is filled less than its nominal capacity as it is slightly larger than copybuffer,
	// this is due to copybuffer optimizations.

	
	auto sw = StopWatch();

	sw.start;
	foreach(i; 0..runs)
	{
		scope const _temp = buffer("");
		_temp.deinit; // Ensure deconstruction is properly included in benchmark
	}
	sw.stop;

	const bufcon = sw.peek/runs;
	writeln("Bench [circlebuf construction + destr]:",bufcon);


	sw.reset;

	sw.start;

	sbuffer ~= (data((sbuffer.max-2)/2));
	foreach(i; 0..runs)
	{
		sbuffer ~= (data((sbuffer.max-2)/2));
		sbuffer = sbuffer[$/2..$]; // Consume half of the data
		sbuffer ~= '|';
		sbuffer = sbuffer[1..$];
	}
	sw.stop;

	const bufrun = sw.peek/runs;
	writeln("Bench [circlebuf runtime]:",bufrun);



	sw.reset;
	sw.start;
	foreach(i; 0..runs)
		scope const _temp = StaticCopyBuffer!()();
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

	static assert((sbuffer.max - 2) == cbuffer.max);

	assert(sbuffer.length == cbuffer.length, "Buffer lengths do not match.");

	assert(sbuffer == cbuffer);


	// PERSONAL NOTES:
	// General: Copy buffer is better when buffer reuse is not possible due to slow circlebuf construction.
	// AMD A8: Linux implementations were cpu bound on AMD A8. Win mem allocation is 3x slower than lin.
	// Results can be found below.

	/+

	Windows 10 - AMD A8-6410 x64 - 4GB memory - LDC release, 100k runs.
	
	Bench [circlebuf construction + destr]:75 ╬╝s and 3 hnsecs
	Bench [circlebuf runtime]:167 ╬╝s and 7 hnsecs
	Bench [copybuf construction + destr]:15 ╬╝s and 7 hnsecs
	Bench [copybuf runtime]:185 ╬╝s and 3 hnsecs

	Reuses needed: 3

	Linux MX-18.3 (Glibc) - AMD A8-6410 x64- 4GB memory - DMD release -nobounds, 100k runs.

	Bench [circlebuf construction + destr]:24 μs and 4 hnsecs
	Bench [circlebuf runtime]:18 μs and 9 hnsecs
	Bench [copybuf construction + destr]:2 μs and 9 hnsecs
	Bench [copybuf runtime]:19 μs and 3 hnsecs

	Reuses needed: 53

	Linux MX-18.3 (Posix) - AMD A8-6410 x64 - 4GB memory - DMD release -nobounds, 100k runs.

	Bench [circlebuf construction + destr]:36 μs and 3 hnsecs
	Bench [circlebuf runtime]:19 μs
	Bench [copybuf construction + destr]:2 μs and 9 hnsecs
	Bench [copybuf runtime]:19 μs and 4 hnsecs

	Reuses needed: 83
	+/

}



