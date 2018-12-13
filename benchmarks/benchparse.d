module benchparse;

static import buffer;
import source;

import std.stdio;

void main()
{
	import std.datetime.stopwatch : StopWatch, Duration;

	auto sw = StopWatch();

	enum runs = 5000;

	Duration bestDur = Duration.max;

	foreach (i; 1 .. runs + 1)
	{

		//auto src = NetSource!()("ite.org");
		auto buffer = buffer.create;
		auto src = "192.168.1.1".NetSource!({});

		scope bool alive = buffer.fill(src);
		debug buffer.writeln;

		assert(buffer.length >= 0);

		scope ptrdiff_t len = void;

		sw.start();

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
					sw.stop;

					buffer.length == buffer.pagesize ? buffer.flush : { }; // Overflow

					alive = buffer.fill(src);

					sw.start;
				}
				else
					break;

			}
			else if (alive)
			{
				buffer.fill("<p>Getting more data!</p>");
				sw.stop;

				buffer.length == buffer.pagesize ? buffer.flush : {  };

				// If this returns true and this is a blocking source, you may assume length = buf_max
				alive = buffer.fill(src);

				sw.start;
			}
			else
				break;

		}

		sw.stop;

		if (bestDur > sw.peek / i)
			bestDur = sw.peek / i;

		writeln(i, '-', buffer.length);
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
