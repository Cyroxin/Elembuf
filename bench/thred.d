module thred;


void thredmain()
{
	import std.stdio;
	import std.datetime.stopwatch;
	import core.time : dur;
	import elembuf;
	import source : NetSource;
	import std.conv : to;
	import std.string : indexOf;

	writeln("Starting threaded/un-threaded comparison");


	
	auto src = (char[] x) 
	{
		import std.random;

		auto rnd = Random(unpredictableSeed);

		foreach(ref c; x)
			c = cast(typeof(c)) rnd.front;
		return x.length;
	};

/+
	auto src = (char[] x) 
	{
		foreach(i; 0 .. x.length)
			x[i] = cast(typeof(x[i])) i;

		return cast(ptrdiff_t) x.length;
	};
+/

	// INFO:
	// The benchmark is for comparing internal threaded and unthreaded performance.
	// It will take exactly 60 seconds. 
	// Result analysis: Threaded buffer should perform better when receiving or processing source data takes time.

	//Threaded buffer processed bytes:		108923014	time:	30 secs and 1 Î¼s
	//Unthreaded buffer processed bytes:	4385951		time:	30 secs, 1 Î¼s, and 9 hnsecs


	auto sw = StopWatch();

	ulong popped;
	ulong poppedThreaded;



	{
		scope auto threadedbuf = tbuffer("");
		threadedbuf ~= src;


	sw.start;

	while(sw.peek() < dur!"seconds"(30))
	{

		// Fill when needed
		threadedbuf ~= threadedbuf.source;

		// Pop
		if(threadedbuf.length > 0)
		{
			threadedbuf = threadedbuf[1..$];
			poppedThreaded++;
		}
		
	}

	sw.stop;
	threadedbuf.deinit; 

	writeln("Threaded buffer processed bytes:	", poppedThreaded, "	time:	", sw.peek());

	sw.start;

	}


	{
	scope auto buf = buffer("");
	sw.reset;

	while(sw.peek() < dur!"seconds"(30))
	{

		// Fill when needed.
		buf ~= src;
		
		// Pop
		if(buf.length > 0)
		{
			buf = buf[1..$];
			popped++;
		}
		
	}

	sw.stop;

	buf.deinit;
	}

	writeln("Unthreaded buffer processed bytes:	", popped, "	time:	", sw.peek());

	writeln("--- Finished ---");
}
