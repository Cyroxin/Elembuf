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







/+ 
This is a conventional buffer that should not be used in applications.
It is used purely for internal benchmarking when comparing a
circular buffer implementation with copying buffers.
+/ 
struct StaticCopyBuffer(InternalType = char)
{
	alias T = InternalType;
	/// Number of bytes per page of memory. Use max!T instead.

	version (Windows)
		private enum pagesize = 65_536; // This is actually allocation granularity, memory maps must be power of this.
	else {
		// Other platforms do not have allocation granularity, but only pagesize.
		version (AnyARM)
		{
			version (iOSDerived)
				private enum pagesize = 16384;
			else
				private enum pagesize = 4096;
		}
		else
			private enum pagesize = 4096;

	}

	// Page bit or pagesize in WINDOWS: xxxx ... xxx1 0000 0000 0000 0000
	// Page bit or pagesize in POSIX: xxxx ... xxx1 0000 0000 0000
	// Page bits in WINDOWS: xxxx ... 1111 1111 1111 1111
	// Page bits in POSIX: xxxx ... 1111 1111 1111

	private enum pagebits = pagesize - 1;  /// Returns the bits that the buffer can write to.
	private enum membits = -pagesize; /// Returns the bits that signify the page position.
	enum max = (pagesize / T.sizeof) - 2; // Returns the maximum size of the buffer depending on the size of T.
	nothrow @nogc @trusted size_t avail() { return max - buf.length;} // Returns how many T's of free buffer space is available.
	nothrow @nogc @trusted @property void length(size_t len) {buf = buf[0..len];} // Overidden so that it can be @nogc
	nothrow @nogc @trusted @property size_t length() {return buf.length;}

	// Max is less than truly, so that page traversal is not possible after popping max items.

	T[] buf;
	alias buf this;

	static assert(typeof(this).sizeof == (T[]).sizeof);

	static typeof(this) opCall() @nogc @trusted nothrow 
	{

		scope T[] ret;

		version (Windows)
		{
			//pragma(msg, "Windows");

			import core.sys.windows.winbase : VirtualAlloc;
			import core.sys.windows.windef : MEM_RELEASE, MEM_COMMIT, PAGE_READWRITE, NULL;

			// Find a suitable large memory location in memory.

			do
			{
				ret = cast(T[]) VirtualAlloc(NULL, pagesize, MEM_COMMIT, PAGE_READWRITE)[0 .. 0]; // TODO: [0..0] & cast compiler optimise?

				debug
				{
					import core.sys.windows.winbase : GetLastError;
					// import core.sys.windows.windef => Check error code from here;
					// https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-

					if ( ret.ptr == NULL )
						const a = GetLastError; // Check this in debugging
				}

			}
			while(ret.ptr == NULL); // Outofmem
		}

		else version (Posix)
		{
			//pragma(msg, "Posix");

			import core.sys.posix.sys.mman : mmap, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_FAILED, MAP_ANON;


			ret = cast(T[]) mmap(cast(void*) 0, pagesize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)[0.. 0];
			assert(ret.ptr != MAP_FAILED); //Outofmem
		}

		else
			static assert(0, "Not supported");

		assert(ret.length == 0);
		return *(cast(typeof(this)*) &ret);
	}

	static typeof(this) opCall(scope const T[] init) nothrow @nogc @trusted
	{
		auto ret = opCall();
		ret.fill!true(init); // Will simply add to the end, not copy all existing to start as there is nothing.
		return ret;

	}


	unittest 
	{
		import elembuf, source;

		scope bufchar = StaticCopyBuffer!()(); // Create buffer
		assert(bufchar == "");

		scope StaticCopyBuffer!int bufint = StaticCopyBuffer!int(); // Create buffer
		assert(bufint == []);

		scope StaticCopyBuffer!char fakebufchar = "Hello World!"; // Create buffer and .fill("Hello World!")
		assert(fakebufchar.avail == fakebufchar.max - "Hello World!".length);

		scope StaticCopyBuffer!int fakebufint = [1,2,3,4,5]; // Create buffer and .fill([1,2,3,4,5])
		assert(fakebufint.avail == fakebufint.max - ([1,2,3,4,5]).length);		

		scope StaticCopyBuffer!char fakebufcharlong = StaticCopyBuffer!char("Hello World!"); // Create buffer and fill("Hello World!")
		assert(fakebufcharlong.avail == fakebufcharlong.max - "Hello World!".length);

		scope StaticCopyBuffer!int fakebufintlong = StaticCopyBuffer!int([1,2,3,4,5]); // Create buffer and .fill([1,2,3,4,5])
		assert(fakebufintlong.avail == fakebufintlong.max - ([1,2,3,4,5]).length);		
	}


	~this() @nogc @trusted nothrow
	{
		assert(buf.ptr !is null); // If this is hit, the destructor is called more than once. Performance decreases by two if true, but will run in release. 

		version (Windows)
			static assert((cast(ptrdiff_t) 0xFFFF0045 & membits) == 0xFFFF0000);
		version (linux)
			static assert((cast(ptrdiff_t) 0xFFFFF045 & membits) == 0xFFFFF000);

		buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & membits))[0..buf.length]; //Set the buffer to page start so that the os unmapper will work.

		version (Windows)
		{
			import core.sys.windows.windef : MEM_RELEASE;
			import core.sys.windows.winbase : VirtualFree;

			VirtualFree(buf.ptr, 0, MEM_RELEASE); // Works for committed memory
			// => Oddly MEM_DECOMMIT will fail to release memory fast enough on x86 and
			// will cause outofmemory before 100k runs.
		}

		else version (Posix)
		{
			import core.sys.posix.sys.mman : munmap;

			munmap(buf.ptr, pagesize);
		}

		else
			static assert(0, "System not supported");
	}

	void opAssign(scope const T[] newbuf) nothrow @nogc @trusted
	{
		buf = (cast(T*) newbuf.ptr) [0..newbuf.length];
	}

	// Fill the buffer with data, pops is the popcount after last fill or construction.
	// isSafe => pops + buf.length + this.avail <= buf.max
	// isOptimal => pops >= buf.length
	void fill(bool isSafe = false, bool isOptimal = false, Source)(scope const size_t delegate(T[]) source)
	{
		static if(!isSafe)  // Old data to start of buffer. Resets pop count.
		{
			static if(!isOptimal) // Copying will overlap with itself
			{
				// Memmove
				//((cast(T*)((cast(ptrdiff_t) buf.ptr) & membits))[0..buf.length]) = buf[];
				import core.stdc.string : memmove;
				memmove((cast(T*)((cast(ptrdiff_t) buf.ptr) & membits)),buf.ptr, buf.length);
			}
			else
				// Memcpy. In windows is the same as memmove.
				(cast(T*)(cast(ptrdiff_t) buf.ptr & membits))[0..buf.length] = buf[];

			buf = (cast(T*)(cast(ptrdiff_t)buf.ptr & membits))[0..buf.length];
		}

		// Fill the empty area of the buffer. Returns neg, an error occurred or 0, there is no more data.
		static if(!isSafe) // Safety measures were added
			scope const len = source((buf.ptr + buf.length)[0 .. this.avail]);
		else
			scope const len = source((buf.ptr + buf.length)[0 .. this.max - (((cast(ptrdiff_t)buf.ptr) & pagebits) + buf.length)]);

		assert(len <= max);

		buf = buf.ptr[0 .. buf.length + len];
	}

	// Fill the buffer with data, pops is the popcount after last fill or construction.
	// isSafe => pops + buf.length + arr.length <= buf.max
	// isOptimal => pops >= buf.length

	void fill(bool isSafe = false, bool isOptimal = false)(scope const T[] arr) nothrow @nogc @trusted
	{
		assert(arr.length <= this.avail);

		static if(!isSafe)  // Old data to start of buffer. Resets pop count.
		{
			static if(!isOptimal) // Copying will overlap with itself
			{
				// Memmove
				import core.stdc.string : memmove;
				memmove((cast(T*)((cast(ptrdiff_t) buf.ptr) & membits)),buf.ptr, buf.length);
			}
			else
				// Memcpy. In windows is the same as memmove.
				(cast(T*)(cast(ptrdiff_t) buf.ptr & membits))[0..buf.length] = buf[];

			buf = (cast(T*)(cast(ptrdiff_t)buf.ptr & membits))[0..buf.length];
		}

		// New data to end of buffer
		(cast(T*)((cast(ptrdiff_t)buf.ptr) + buf.length)) [0 .. arr.length] = cast(T[]) arr[];
		buf = buf.ptr[0..buf.length + arr.length];

	}
}