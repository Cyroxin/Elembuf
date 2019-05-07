module parse;

import buffer, source;
import std.stdio;

void main(){
	import std.datetime.stopwatch : benchmark, Duration;

	enum runs = 100_000;
	auto time = benchmark!(html)(runs);

	foreach(size_t i; 0..1)
		writeln(time[i] / runs);

	readln;

}


void html(){
		import std.range : repeat;
		import std.array : join;

		// Create the buffer
		scope buffer = StaticBuffer!()();

		// Create the source
		// scope src = "192.168.1.1".NetSource!(); // Not suitable for benchmarking as contents vary and change.
		auto src = new ArraySource!string("<html>" ~ cast(string) "<node></node>".repeat(1000).join ~ "</html>");


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

		if (buffer.length > 0)
			buffer.writeln;

}

/// Compile time needle occurence finder.
ptrdiff_t indexOf(alias needle, T)(scope const T[] arr) pure nothrow @nogc
{
	foreach (ref i, c; arr)
		if (c == needle)
			return i;
	return -1;
}
