module parse;

import buffer, source;
import std.stdio;

void main()
{
	import std.datetime.stopwatch : benchmark, Duration;

	enum runs = 100_000;
	auto time = benchmark!(html,cons)(runs);

	writeln("Benchmarks unrelated to eachother, used for improving the system.");
	writeln("Bench [Overall]: ",time[0] / runs);
	writeln("Bench [Construction]: ",time[1] / runs);

	readln;

	// PERSONAL NOTES!

}

/// Used for benchmarking overall performance, which includes construction and core functions.
void html() @nogc
{
		static import std.range;
		static import std.array;

		// Create the buffer
		auto buffer = StaticBuffer!()();

		enum data = "<html>" ~ cast(string) std.array.join(std.range.repeat("<node></node>",1000)) ~ "</html>";

		// Create the source
		// scope src = "192.168.1.1".NetSource!(); // Not suitable for benchmarking as contents vary and change.
		auto src = ArraySource!string(data);


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
					buffer.length == buffer.max!char ? buffer.clear : {}; // Overflow management

					alive = buffer.fill(src);
				}
				else
					break;

			}
			else if (alive)
			{
				buffer.length == buffer.max!char ? buffer.clear : {}; // Overflow management

				alive = buffer.fill(src);
			}
			else
				break;
		}
}

/// Used for benchmarking construction.
void cons() @nogc
{
	auto buffer = StaticBuffer!()();
}

/// Compile time needle occurence finder.
ptrdiff_t indexOf(alias needle, T)(scope const T[] arr) pure nothrow @nogc
{
	foreach (ref i, c; arr)
		if (c == needle)
			return i;
	return -1;
}
