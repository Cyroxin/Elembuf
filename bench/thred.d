module thred;


void thredmain()
{
	import std.stdio;
	import std.datetime.stopwatch;
	import core.time : dur;
	import buffer;
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

/*
	auto src = (char[] x) 
	{
		foreach(i; 0 .. x.length)
			x[i] = cast(typeof(x[i])) i;

		return cast(ptrdiff_t) x.length;
	};
*/

	// INFO:
	// The benchmark is for comparing internal threaded and unthreaded performance.
	// It will take exactly 60 seconds. 
	// Result analysis: Threaded buffer should perform better when receiving or processing source data takes time.


	auto sw = StopWatch();

	ulong popped;
	ulong poppedThreaded;



	{
		scope Buffer!(char, true) threadedbuf = "";
		threadedbuf.fill = src;


	sw.start;

	while(sw.peek() < dur!"seconds"(30))
	{

		// Fill when needed
		threadedbuf.fill();

		// Pop
		if(threadedbuf.length > 0)
		{
			threadedbuf = threadedbuf[1..$];
			poppedThreaded++;
		}
		
	}

	sw.stop;

	writeln("Threaded buffer processed bytes:	", poppedThreaded, "	time:	", sw.peek());

	sw.start;

	}


	{
	scope Buffer!(char,false) buf = "";
	sw.reset;

	while(sw.peek() < dur!"seconds"(30))
	{

		// Fill when needed.
		buf.fill(src);
		
		// Pop
		if(buf.length > 0)
		{
			buf = buf[1..$];
			popped++;
		}
		
	}

	sw.stop;

	}

	writeln("Unthreaded buffer processed bytes:	", popped, "	time:	", sw.peek());

	writeln("--- Finished ---");
}