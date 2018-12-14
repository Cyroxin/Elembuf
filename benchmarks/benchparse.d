module benchparse;

import buffer, source;

import std.stdio;

void main()
{
	import std.datetime.stopwatch : StopWatch, Duration;

	auto sw = StopWatch();

	enum runs = 5000;

	Duration bestDur = Duration.max;

	foreach (i; 1 .. runs + 1)
	{
		auto src = "192.168.1.1".NetSource!();
		auto buffer = StaticBuffer!()();
		buffer.initiate;

		sw.start();

		scope bool alive = buffer.fill(src);
		scope ptrdiff_t len = void;

		while (true)
		{
			len = buffer.indexOf!'<';

			if (len > -1)
			{
				// Parse html
				buffer = buffer[len .. $];
				len = buffer.indexOf!'>';

				if (len > -1)
					buffer = buffer[len + 1 .. $];
				else if (alive)
				{
					buffer.fill("<p>Getting more data!</p>");

					buffer.length == buffer.pagesize ? buffer.flush : {}; // Overflow management

					alive = buffer.fill(src);
				}
				else
					break;

			}
			else if (alive)
			{
				buffer.fill("<p>Getting more data!</p>");

				buffer.length == buffer.pagesize ? buffer.flush : {}; // Overflow management

				alive = buffer.fill(src);
			}
			else
				break;

		}

		sw.stop;

		if (bestDur > sw.peek / i)
			bestDur = sw.peek / i;

		writeln(i);
		if (buffer.length > 0)
			buffer.writeln;

		buffer.deinitiate;
		src.deinitiate;
	}

	writeln("Average Time: ", sw.peek / runs);
	writeln("Best Time: ", bestDur);

	readln;

}

/// Compile time needle occurence finder.
ptrdiff_t indexOf(alias needle, T)(scope const T[] arr) pure nothrow @nogc
{
	foreach (ref i, c; arr)
		if (c == needle)
			return i;
	return -1;
}
