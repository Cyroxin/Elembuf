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

// Keep runs at least this high for accurate results
// Run count is highly dependant on your own machine.
// Increasing it will help in determining benchmark results.
debug enum runs = 100_000;
else enum runs = 1_000_000;


// Construction timings can vary drastically due to changes in memory availabillity.
// Using a high run count mitigates the variance as average construction can be calculated.

void implemmain()
{
	import std.datetime.stopwatch;
    writeln("runs: ",runs);

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
    
    
	const bufcon = sw.peek;
	writeln("Bench [buffer construction + destr]:",bufcon/runs);


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

	const bufrun = sw.peek;
	writeln("Bench [buffer runtime]:",bufrun/runs);



	sw.reset;
	sw.start;
	foreach(i; 0..runs)
		scope const _temp = StaticCopyBuffer!()();
	sw.stop;

	const cbufcon = sw.peek;

	writeln("Bench [array construction + destr]:",cbufcon/runs);


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

	const cbufrun = sw.peek;

	writeln("Bench [array runtime]:",cbufrun/runs);



	writeln("\nReuses needed: ",((bufcon-cbufcon)/(cbufrun-bufrun))); // To make usage worth it

	static assert((sbuffer.max - 2) == cbuffer.max);

	assert(sbuffer.length == cbuffer.length, "Buffer lengths do not match.");

	assert(sbuffer == cbuffer);


	// PERSONAL NOTES:
	// General: Copy buffer is better when buffer reuse is not possible due to slow circlebuf construction.
	// AMD A8: Linux implementations were cpu bound on AMD A8. Win mem allocation is 3x slower than lin.
	// Results can be found below.

	/+

	Windows 10 - AMD A8-6410 x64 - 4GB memory - LDC release, 100k runs.
	
	Bench [buffer construction + destr]:110 Î¼s and 6 hnsecs
	Bench [buffer runtime]:111 Î¼s and 9 hnsecs
	Bench [array construction + destr]:23 Î¼s and 9 hnsecs
	Bench [array runtime]:141 Î¼s and 4 hnsecs

	Reuses needed: 2

	Linux MX-18.3 (Glibc) - AMD A8-6410 x64- 4GB memory - DMD release -nobounds, 100k runs.

	Bench [buffer construction + destr]:24 μs and 4 hnsecs
	Bench [buffer runtime]:18 μs and 9 hnsecs
	Bench [array construction + destr]:2 μs and 9 hnsecs
	Bench [array runtime]:19 μs and 3 hnsecs

	Reuses needed: 53

	Linux MX-18.3 (Posix) - AMD A8-6410 x64 - 4GB memory - DMD release -nobounds, 100k runs.

	Bench [buffer construction + destr]:36 μs and 3 hnsecs
	Bench [buffer runtime]:19 μs
	Bench [array construction + destr]:2 μs and 9 hnsecs
	Bench [array runtime]:19 μs and 4 hnsecs

	Reuses needed: 83
	+/

}



