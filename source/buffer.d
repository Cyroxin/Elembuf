/**
* <a href="https://cyroxin.github.io/Elembuf/source.html"><</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/buffer.html">docs/buffer</a>
*/

module elembuf;

import std.traits : isArray;


/**
* Dynamic circular array with a maximum length. $(BR) $(BR)
* $(P $(BIG  Takes an advantage of the system's memory mirroring capabillities to
* create a memory loop so that memory copying wont be necessary.
* The buffer may be manipulated normally as if it were a T[] and can be implicitly converted to it.))
*
*
*				- $(BIG The concat operator cannot be used in @nogc code, but it does not use the GC.)
*				- $(BIG  <b style="color:blue;">[WINDOWS]</b> Only one instance allowed. Additional will become slices of the original buffer. ) 
* $(BR)
* - - -
*
*/

/++ $(BR) $(BIG $(B Whole library can be used in 5 lines. No new methods to remember while beating the efficiency of arrays and queues.)) $(BR) $(BR) +/
unittest
{

	// Import
	import elembuf;

	// Instantiate
	auto buf = buffer("Hello ");

	// Ensure new data fits
	assert(buf.max >= "world!".length + buf.length); 

	// Fill
	buf ~= "world!";

	// Read
	assert(buf == "Hello world!");
}

/++ $(BR) $(BIG $(B IO - Fast library integration))

$(BIG  There is no need to create a new container just so outdated push/pop queues and lists can work with socket and file system libraries that require pointers. Just use a lambda! ) $(BR) $(BR)

- - -
$(BR) 
+/
unittest
{
	// Construct
	auto buf = buffer([1,2,3]);

	auto source = (int[] array) { array[0] = 4; return 1;}; //  Give array.ptr to socket.receive if using sockets. Return written.

	// Fill
	buf ~= source;
	assert(buf == [1,2,3,4]);

	// Reuse
	buf.length = 0;
	buf ~= source;
	buf ~= 5;
	assert(buf == [4,5]);
} 

/++ $(BR) $(BIG $(B Design - Type freedom))

$(BIG  Types should be easy to use by the user, not obscure behind a type deduction declaration.) $(BR) $(BR)

- - -
$(BR) 
+/
unittest
{
	buffer!(char[], false) buf = buffer("");

	buffer!(char[], true) tbuf = tbuffer("");
	scope(exit) tbuf.deinit;

	shared buffer!(char[], false) csbuf = buffer("");
	const buffer!(char[], false) cibuf = buffer("");

} 

/++ $(BR) $(BIG $(B Concurrency - Built in for your convenience))

$(BIG  Simple solution that works efficiently out of the box. Syncronized in the background without need for fiddling.) $(BR) $(BR)

- - -
$(BR) 
+/
unittest
{

	auto buf = tbuffer((size_t[]).init); // Producer thread created and syncronized

	size_t counter;

	size_t delegate(size_t[]) source = (size_t[] array) 
	{ 
		foreach(ref i; array)
		{
			i = counter;
			counter++;
		}

		return array.length;
	};

	buf ~= source; // Give instructions to producer


	for(int i; i < buf.max * 5; )
	{
		while(buf.length == 0) 
			buf ~= buf.source; // Aquire data from producer

		i += buf.length;
		buf = buf[$..$];
	}

	buf.deinit; // Unallocates all data, including destroying the thread. Can be used for all buffers.
}


/+++

$(BR) $(BIG $(B Mirroring - For Compression & Decryption))

$(BIG  New item orders can easily be established without copying using a mirror provided natively by the operating system. ) $(BR) $(BR)

- - -

$(BR) $(BR) $(BIG We can represent memory as blocks of two $(BIG $(B O))'s, each having a size of $(BIG $(D_INLINECODE max/2)). The buffer only sees memory marked with $(BIG $(B X))'s. $(BR) 
The mirror border is marked with $(BIG $(B |)), right side of which is the mirrored memory. )

+/
unittest
{
	/+ Current view is OO|OO +/
	auto buf = buffer("");

	// aO|aO
	buf.ptr[0..buf.max/2] = 'a';

	// ab|ab
	buf.ptr[buf.max/2 .. buf.max] = 'b';

	/+ Expand view from OO|OO +/

	// OX|XO
	buf = buf.ptr[buf.max/2..buf.max+buf.max/2];

	// ab|ab
	assert(buf[0] == 'b' && buf[$-1] == 'a');

	/+ Order: ab -> ba +/
} 






auto buffer(A)(A arg)
{
	import std.traits : isMutable, Unqual, ForeachType, InoutOf;

	return buffer!(Unqual!(ForeachType!A)[], false)(arg);

}


auto tbuffer(A)(A arg)
{
	import std.traits : isMutable, Unqual, ForeachType, InoutOf;

	return buffer!(Unqual!(ForeachType!A)[], true)(arg);

}





private struct buffer(ArrayType, bool threaded)
if(isArray!(ArrayType))
{
	import std.traits : isMutable, Unqual, ForeachType, InoutOf;
	//debug import std.stdio : writeln;

	alias T = Unqual!(ForeachType!ArrayType);

	//pragma(msg,"root: ", threaded, " - ", ArrayType, " - ", T);

	T[] buf;
	alias buf this;

	static if (threaded)
		align(mail.sizeof) __gshared ptrdiff_t mail = 0; // Thread sync variable, must fit a pointer.
	else
		static assert(typeof(this).sizeof == (T[]).sizeof);

	

	this(Unqual!T[] arr) shared
	{
		//debug writeln("1 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate().ptr[0..arr.length];
		tempbuf[] = arr[];
		buf = cast(shared) tempbuf;
	}

	this(Unqual!T[] arr)
	{
		//debug writeln("3 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate().ptr[0..arr.length];
		tempbuf[] = arr[];
		buf = tempbuf;

		static if(threaded)
		{
			import std.parallelism : taskPool, task;
			taskPool.put(task!initWriter(buf.ptr,&mail));
		}
	}

	this(inout Unqual!T[] arr) shared
	{
		//debug writeln("4 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate().ptr[0..arr.length];
		tempbuf[] = arr[];
		buf = cast(shared) tempbuf;
	}

	this(inout Unqual!T[] arr)
	{
		//debug writeln("5 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate().ptr[0..arr.length];
		tempbuf[] = arr[];
		buf = tempbuf;

		static if(threaded)
		{
			import std.parallelism : taskPool, task;
			taskPool.put(task!initWriter(buf.ptr,&mail));
		}
	}


	
	static initiate() @nogc @trusted nothrow
	{
		T[] ret;

		version (Windows)
		{
			//pragma(msg, "Windows");

			import core.sys.windows.winbase : CreateFileMapping, VirtualAlloc,
				VirtualFree, MapViewOfFileEx, UnmapViewOfFile, CloseHandle,
				INVALID_HANDLE_VALUE, FILE_MAP_ALL_ACCESS;
			import core.sys.windows.windef : MEM_RELEASE, MEM_RESERVE,
				PAGE_READWRITE, NULL;

			// Create a file in memory, which we read using two pagesize buffers that are next to each other.
			scope const void* memfile = CreateFileMapping(INVALID_HANDLE_VALUE,
														  NULL, PAGE_READWRITE, 0, pagesize, NULL);

			debug
			{
				import core.sys.windows.winbase : GetLastError;
				import core.sys.windows.windef :ERROR_ALREADY_EXISTS;
				assert(GetLastError != ERROR_ALREADY_EXISTS,"[WINONLYERR] There are multiple type instances that create files to memory. Either destroy existing or use another buffer type.");
			}

			do
			{
				// Find a suitable large memory location in memory. TODO: Dropping win7 compatab will allow this to be automated by the os.
				ret = cast(T[]) VirtualAlloc(NULL, pagesize * 3, MEM_RESERVE, PAGE_READWRITE)[0..0];
				assert(ret.ptr != NULL); // Outofmem

				// Select a page with a pagebit of 0.
				if ((cast(ptrdiff_t) ret.ptr & pagesize) == pagesize) // Pagebit 1, next is 0, final 1
				{
					ret = (cast(T*)((cast(ptrdiff_t) ret.ptr) + pagesize))[0..0];
					VirtualFree(cast(void*)((cast(ptrdiff_t) ret.ptr) - pagesize), 0, MEM_RELEASE);
				}
				else // Pagebit 0, next 1, third 0
					VirtualFree(cast(void*)ret.ptr, 0, MEM_RELEASE);


				// Map two contiguous views to point to the memory file created earlier.
				if (!MapViewOfFileEx(cast(void*) memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*) ret.ptr))
					continue;
				else if (!MapViewOfFileEx(cast(void*) memfile,FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*)((cast(ptrdiff_t)ret.ptr) + pagesize)))
					UnmapViewOfFile(cast(void*) ret.ptr);
				else
					break;
			} while(true);

			CloseHandle(cast(void*) memfile); // This will destroy the mapfile once there are no mappings


		}


		else version (memfd) // Linux that supports memfd_create
		{
			//pragma(msg, "CRuntime_Glibc");

			import core.sys.posix.sys.mman : mmap, munmap, PROT_NONE, PROT_READ,
				PROT_WRITE, MAP_PRIVATE, MAP_SHARED, MAP_FIXED, MAP_FAILED,
				MAP_ANON;
			import core.sys.posix.unistd : ftruncate, close;

			// Memfd_create file descriptors are automatically collected once references are dropped,
			// so there is no need to have a memfile global.
			scope const int memfile = memfd_create("elembuf", 0);
			assert(memfile != -1); // Outofmem

			ftruncate(memfile, pagesize);

			// Create a two page size memory mapping of the file
			ret =  cast(T[]) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0..0];
			assert(ret.ptr != MAP_FAILED); // Outofmem

			if ((cast(ptrdiff_t)ret.ptr & pagesize) == 0) // First page is 0, second 1, third 0
			{
				// Sub map it to two identical consecutive maps
				mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize * 2), pagesize);
			}
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize))[0..ret.length];

				// Sub map it to two identical consecutive maps
				mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*) ((cast(ptrdiff_t)ret.ptr) - pagesize), pagesize);
			}

			close(memfile); // Will only truly close once maps are closed. Documentation in manpages is lacking in regards to this.
		}


		else version (Posix)
		{
			//pragma(msg, "Posix");

			import core.sys.posix.sys.mman : shm_open, shm_unlink, mmap, munmap,
				PROT_NONE, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_SHARED,
				MAP_FIXED, MAP_FAILED, MAP_ANON;

			import core.sys.posix.unistd : ftruncate, close; // Memory file management

			import core.sys.posix.fcntl : S_IWUSR, S_IRUSR, O_RDWR, O_CREAT,
				O_EXCL; // Permissions for shm_open

			/+ Name reservation for memory file +/

			static assert(ubyte.sizeof == char.sizeof);

			enum iname = cast(char[]) "/elbu-" ~ cast(char)0 ~ cast(char)0; // 8 bytes reduces fragmentation.
			scope char[8] hname = iname;
			scope int memfile = void;

			static foreach (i; char.min + 1 .. char.max)
			{
				// Create a memory file
				memfile = shm_open(hname.ptr, O_RDWR | O_CREAT | O_EXCL, S_IWUSR | S_IRUSR);
				if (memfile >= 0)
					goto success;

				static if(i != char.max)
					hname[$ - 2] = i;
			}
			assert(0); // nomem

		success:
			shm_unlink(hname.ptr);

			ftruncate(memfile, pagesize); // Sets the memory file length

			// Create a two page size memory mapping of the file
			ret = cast(T[]) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0..0];
			assert(ret.ptr != MAP_FAILED); // Outofmem

			if ((cast(ptrdiff_t)ret.ptr & pagesize) == 0) // First page is 0, second 1, third 0
			{
				// Sub map it to two identical consecutive maps
				mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize * 2), pagesize);
			}
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize))[0..ret.length];

				// Sub map it to two identical consecutive maps
				mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*) ((cast(ptrdiff_t)ret.ptr) - pagesize), pagesize);
			}

			close(memfile); // Deallocates memory once all mappings are unmapped
		}

		else
			static assert(0, "Operating system not supported");


		return ret;
	}

	public inout void deinit() @nogc @trusted nothrow
	{

		assert(buf.ptr != null);  // If this is hit, the destructor is called more than once. Performance decreases if true, but will run in release. 

		static if(threaded)
		{
			const nulldelg = cast(size_t delegate(T[])) null; // Shorthand for terminate worker thread

			import core.atomic;

			mail.atomicStore!(MemoryOrder.raw)(cast(typeof(mail)) max + 1); // Alert thread
			while (mail.atomicLoad!(MemoryOrder.raw)() == cast(typeof(mail)) max + 1){} // Wait till thread ready

			mail.atomicStore(cast(typeof(mail)) &nulldelg); // Give source to thread
			while (mail.atomicLoad!(MemoryOrder.raw) != 0){} // Wait till thread ready
		}

		version (Windows)
			static assert((cast(ptrdiff_t) 0xFFFF0045 & (membits & (~pagesize))) == 0xFFFE0000);
		version (linux)
			static assert((cast(ptrdiff_t) 0xFFFFF045 & (membits & (~pagesize))) == 0xFFFFE000);

		//Set the buffer to page start so that the os unmapper will work. TODO: Check if some OS can do this for us.
		auto buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & (membits & (~pagesize))))[0..buf.length];


		version (Windows)
		{
			import core.sys.windows.winbase : UnmapViewOfFile;

			UnmapViewOfFile(buf.ptr);
			UnmapViewOfFile(cast(void*)((cast(ptrdiff_t)buf.ptr) + pagesize));

			// NOTE: There is an EX unmap with priority unmap flag, 
			// but it lacks windows 7 compatibility and is thus not used.
			// Using it in the future could mean that memory is freed quicker.
		}

		else version (CRuntime_Glibc)
		{
			import core.sys.posix.sys.mman : munmap;

			munmap(buf.ptr, pagesize * 2);
		}

		else version (Posix)
		{
			import core.sys.posix.sys.mman : munmap;

			munmap(buf.ptr, pagesize * 2);
		}

		else
			static assert(0, "System not supported");

	}

	//static assert(typeof(this).sizeof == (T[]).sizeof, "BufErr: Buffer internal size is larger than an array!"); // Allows casting

	// OVERRIDES

	public void opOpAssign(string op : "~")(inout T[] rhs)
		if(!threaded)
		{
			assert(buf.length + rhs.length <= max,"BufErr: Not enough space available to fill the buffer. Buf must be at most .max(), available space can be checked using .avail()");

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize)) [0 .. buf.length + rhs.length]; 
			buf[$ - rhs.length .. $] = rhs[];
		}
	public void opOpAssign(string op : "~")(inout T rhs) 
		if(!threaded)
		{
			assert(buf.length + 1 <= max,"BufErr: Not enough space available to fill the buffer. Buf must be at most .max(), available space can be checked using .avail()");

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize)) [0 .. buf.length + 1]; 
			buf[$-1] = rhs;

		}
	
	public void opOpAssign(string op : "~",Source)(Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs(T[].init);}))
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs((cast(T*)((cast(ptrdiff_t)buf.ptr)+buf.length*T.sizeof))[0..this.max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}

	public void opOpAssign(string op : "~",Source)(Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs.src()(T[].init);}))
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs.src()((cast(T*)((cast(ptrdiff_t)buf.ptr)+buf.length*T.sizeof))[0..max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}
	public void opOpAssign(string op : "~",Source)(Source rhs)
		if(threaded) // Threaded - change source
		{
			static if(__traits(compiles, rhs((T[]).init)))
			{
				import std.traits : isDelegate /+, isFunctionPointer+/;

				static if(isDelegate!Source)
				{
					import core.atomic;

					mail.atomicStore!(MemoryOrder.raw)(cast(typeof(mail)) max + 1); // Alert thread
					while (mail.atomicLoad!(MemoryOrder.raw)() == cast(typeof(mail)) max + 1){} // Wait till thread ready

					mail.atomicStore(cast(typeof(mail)) &rhs); // Give source to thread
					while (mail.atomicLoad!(MemoryOrder.raw) != 0){} // Wait till thread ready
				}
				else
				{
					import std.functional : toDelegate;
					import core.atomic;

					auto deleg = toDelegate(rhs);

					mail.atomicStore!(MemoryOrder.raw)(cast(typeof(mail)) max + 1); // Alert thread
					while (mail.atomicLoad!(MemoryOrder.raw)() == cast(typeof(mail)) max + 1){} // Wait till thread ready

					mail.atomicStore(cast(typeof(mail)) &deleg); // Give source to thread
					while (mail.atomicLoad!(MemoryOrder.raw) != 0){} // Wait till thread ready
				}
			}
			else static assert(0, "BufErrThreaded: "~Source.stringof~" is not of type size_t function("~T[].stringof~"), size_t delegate("~T[].stringof~") or it doesn't have a src() -function that returns either of them.");
		}
	public void opOpAssign(string op : "~", Source : typeof(null))(Source rhs) nothrow @nogc @trusted
		if(threaded) // Threaded - fill from source
		{
			import core.atomic : atomicLoad, atomicStore, cas, MemoryOrder;

			assert(buf.length <= max, "BufErrThreaded: Buffer length exceeds capacity or popped when no length");

			scope const i = atomicLoad!(MemoryOrder.raw)(mail);

			if(i > 0) {
				atomicStore!(MemoryOrder.raw)(mail,cast(typeof(mail))-(i+length)); // Aquire more length

				buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0..buf.length + i];
			}
			else if(!cas!(MemoryOrder.raw, MemoryOrder.raw)(&mail,i,-length)){
				scope const x = atomicLoad!(MemoryOrder.raw)(mail);
				atomicStore!(MemoryOrder.raw)(mail,-(x+length)); 

				buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0..buf.length + x];
			}
		}



	void opAssign(scope T[] s)
	{
		assert((cast(ptrdiff_t)s.ptr & mempos) == (cast(ptrdiff_t)buf.ptr & mempos), "BufErr: Setting the buffer to another memory position is not allowed, you can only slice and set slices. ");
		buf = s.ptr[0..s.length];
	}

	// FUNCTIONS

	nothrow @nogc @trusted @property void length(inout size_t len) {buf = buf.ptr[0..len];} // Overidden so that it can be @nogc
	nothrow @nogc @trusted @property auto length() inout {return buf.length;}

	shared nothrow @nogc @trusted @property void length(inout size_t len) {buf = buf.ptr[0..len];} // Overidden so that it can be @nogc
	shared nothrow @nogc @trusted @property auto length() inout {return buf.length;}
	

	// INTERNALS

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
	// Page bit or pagesize in LINUX: xxxx ... xxx1 0000 0000 0000
	// Page bits in WINDOWS: xxxx ... 1111 1111 1111 1111
	// Page bits in LINUX: xxxx ... 1111 1111 1111

	private enum pagebits = pagesize - 1;  // Returns the bits that the buffer can write to.
	private enum membits = -pagesize; // Returns the bits that signify the page position including page bit.
	private enum mempos = membits * 2; // Returns the bits that signify the page position excluding page bit.

	/++
	Maximum amount of items that the buffer can hold. Use this and length to determine how much can be concatenated.
	+/
	enum max = pagesize / T.sizeof; 

	static if(threaded)
		enum source = null;

	// Concurrent background thread
	static void initWriter()(scope const T* ptr, scope typeof(mail)* mailptr)
		if(threaded)
		{
			import core.atomic;

			// Alternative method: Pops = -(previousLenAsNegative - currentLenAsNegative); => source(pops);


			scope size_t delegate(T[]) source = (T[] x) {return 0;};
			scope T* localbuf = cast(T*) ptr;



			while(true)
			{
				// Read mail
				scope const typeof(mail) i = atomicLoad!(MemoryOrder.raw)(*mailptr);


				debug {
					import std.stdio : writeln;
					scope(failure)
					{
						debug writeln("ERROR! THREAD EXITED WITHOUT AGREEMENT WITH MAIN THREAD! ", i);
						assert(0);
					}
				}


				// Got buffer length
				if(cast(typeof(mail)) i <= 0 && cast(typeof(mail)) i != -max) // New length received!
				{
					// Works as i is negative.
					scope const read = source(localbuf[0..(max+i)]);
					assert(read <= max);


					if(read == 0)
						continue;

					// Write amount read to mail so that it may be extended to buffer with call to fill()
					if(atomicExchange!(MemoryOrder.raw)(mailptr, cast(typeof(mail)) read) == cast(typeof(mail)) max + 1)
					{

						// Order received while writing to mail
						while(atomicLoad!(MemoryOrder.raw)(*mailptr) == cast(typeof(mail)) read){}
						source = *cast(typeof(source)*) atomicLoad!(MemoryOrder.raw)(*mailptr);
						atomicStore!(MemoryOrder.raw)(*mailptr,0); // Assume max data must be read and clear bits

						if(source == null) 
							return; // Order received to terminate.
					}
					else
						localbuf = (cast(T*)((cast(ptrdiff_t)localbuf + read * T.sizeof) & ~pagesize));
				}
				else if(i == cast(typeof(mail)) max + 1) // Order received
				{
					atomicStore!(MemoryOrder.raw)(*mailptr, cast(typeof(mail)) -max);
					while(atomicLoad!(MemoryOrder.raw)(*mailptr) == cast(typeof(mail)) -max){}
					source = *cast(typeof(source)*) atomicLoad!(MemoryOrder.raw)(*mailptr);
					atomicStore!(MemoryOrder.raw)(*mailptr,0); // Assume max data must be read and clear bits


					if(source == null) 
						return; // Order received to terminate.
				}

			} // While

		} //Function



}

// UNITTESTS

// Instantiating, to ensure the doc is not cluttered, this should be showcased elsewhere.
unittest
{
	import std.stdio;
	auto buf = buffer("Hello world!");
	static assert( is(typeof(buf) == buffer!(char[], false)) );

	buffer!(char[], false) bufd = "Hello world!";
	static assert( is(typeof(bufd) == buffer!(char[], false)) );

	const bufc = buffer("Hello world!");
	static assert( is(typeof(bufc) == const buffer!(char[], false)) );

	const buffer!(char[], false) bufcd = "Hello world!";
	static assert( is(typeof(bufcd) == const buffer!(char[], false)) );

	shared bufs = buffer("Hello world!");
	static assert( is(typeof(bufs) == shared buffer!(char[], false)) );

	shared buffer!(char[], false) bufsd = "Hello world!";
	static assert( is(typeof(bufsd) == shared buffer!(char[], false)) );
}

@trusted unittest // Unthreaded
{
	auto bufz = buffer([1,2,3,4,5]);
	static assert( is(typeof(bufz) == buffer!(int[], false)) );

	assert(bufz == [1,2,3,4,5]);

	bufz ~= [6,7,8,9];
	assert(bufz == [1,2,3,4,5,6,7,8,9]);

	bufz ~= 0;
	assert(bufz == [1,2,3,4,5,6,7,8,9,0]);

	bufz.length = 9; 
	assert(bufz == [1,2,3,4,5,6,7,8,9]);

	bufz.deinit;

	auto bufy = buffer((ulong[]).init);
	static assert( is(typeof(bufy) == buffer!(ulong[], false)) );
	bufy ~= 0;
	assert(bufy == [0]);
	bufy.deinit;

}

@trusted unittest // Threaded
{
	auto bufs = tbuffer((int[]).init);
	static assert(is(typeof(bufs) == buffer!(int[], true)));

	auto rhs = cast(size_t delegate(int[])) (int[] x){x[0] = 1; return 1;};
	static assert(__traits(compiles, rhs((int[]).init)));

	bufs ~= (int[] x){x[0] = 1; return 1;}; // Set source
	while(bufs.length == 0) {bufs ~= bufs.source;} // Read from source set earlier

	assert(bufs == [1]);

	bufs.deinit;
}

unittest // Visuald issue
{
	struct test(T) {
		T[] buf;

		this(T[] arr)
		{
			buf = arr;
		}

		void print()
		{
			import std.stdio;
			writeln(buf);
		}
	}

	// TODO: Write up a bug report for visuald, this seems to run well if run without using dmd on debug mode and errors only on windows x64, not on x86. Linux works.
	// Only fails when using visuald, so low priority.

	// The following do not compile in dmd debug, but do on release. Same issue with ushort. LDC works well. Runs on debug as well if set to x86 mode.
	//test!short([1,2,3,4,5]);
	//test!ushort([1,2,3,4,5]);
	//test!double(cast(double[]) [1,2,3,4,5]);
	//test!real(cast(real[]) [1,2,3,4,5]);

	/+ DMD Debug
	error LNK2001: unresolved external symbol "TypeInfo_Axs.__init" (_D12TypeInfo_Axs6__initZ)
	fatal error LNK1120: 1 unresolved externals
	´+/

}


	

unittest {
	auto buf = buffer("Hello World!");
	assert(buf.length == "Hello World!".length);

	assert(buf[$/2..$].length == "World!".length);

	buf.length = "Hello World".length;
	assert(buf == "Hello World");

	buf.length = "Hello".length;
	assert(buf == "Hello");
}


// Usage
unittest 
{
	import elembuf,source;
	import std.stdio;

	// Construct
	auto buf = buffer("");
	static assert(is(typeof(buf) == buffer!(char[], false)));

	auto src = "buf".ArraySource!char;
	size_t delegate(char[]) srclambda = (char[] buffer){buffer[0] = '!'; return 1;};

	// Fill

	buf ~= "-Elem"; 
	assert(buf == "-Elem");

	buf ~= src; 
	assert(buf == "-Elembuf");

	buf ~= srclambda;
	assert(buf == "-Elembuf!");

	// Empty

	buf = buf[5..$];
	assert(buf == "buf!");

	buf.length = 0; 
	assert(buf == "" && buf.ptr[0..4] == "buf!");
	
}







unittest // slices
{
	auto buf = buffer([0,1,2,3,4]);
	int[] a = buf[3..$];
	
	assert(a == [3,4]);
	static assert(!is(typeof(a) == typeof(buf)));
}

unittest // T.sizeof > 1
{
	auto buf = buffer((size_t[]).init);
	static assert(buf[0].sizeof > 1); 

	buf ~= [1,2,3];
	
	auto sum = 0;
	foreach(i; buf) {sum += i;}
	assert(sum == 6);

	buf ~= [1,2,3];
	foreach(i; buf) {sum += i;}

	assert(sum == 6 + 12);

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

unittest // Test all implementations
{
	string data(size_t characters)
	{
		char character = cast(char) 0;

		char[] data;
		data.reserve(characters);
		data.length = characters;

		foreach(i; 0 .. characters)
		{
			data[i] = character;
			character++;
		}

		return cast(string) data;						
	}


	enum fakemax = (char.max+1)*2;

	auto sbuf = buffer("");
	StaticCopyBuffer!char cbuf = "";

	sbuf ~= (data(fakemax));
	cbuf.fill(data(fakemax));

	assert(sbuf[0] == cast(char) 0);
	assert(cbuf[0] == cast(char) 0);
	assert(sbuf[1] == cast(char) 1);
	assert(cbuf[1] == cast(char) 1);
	assert(sbuf[(fakemax) - 2] == cast(char) 254);
	assert(cbuf[(fakemax) - 2] == cast(char) 254);
	assert(sbuf[(fakemax) - 1] == cast(char) 255);
	assert(cbuf[(fakemax) - 1] == cast(char) 255);
	assert(sbuf == cbuf);

	sbuf = sbuf[$/2..$];
	cbuf = cbuf[$/2..$];


	assert(sbuf[0] == cast(char) 0);
	assert(cbuf[0] == cast(char) 0);
	assert(sbuf[1] == cast(char) 1);
	assert(cbuf[1] == cast(char) 1);
	assert(sbuf[(fakemax/2) - 2] == cast(char) 254);
	assert(cbuf[(fakemax/2) - 2] == cast(char) 254);
	assert(sbuf[(fakemax/2) - 1] == cast(char) 255);
	assert(cbuf[(fakemax/2) - 1] == cast(char) 255);

	assert(sbuf == cbuf);
	assert(sbuf.length == cbuf.length);

	sbuf ~= (data(fakemax/2));
	cbuf.fill(data(fakemax/2));

	assert(sbuf[0] == cast(char) 0);
	assert(cbuf[0] == cast(char) 0);
	assert(sbuf[1] == cast(char) 1);
	assert(cbuf[1] == cast(char) 1);
	assert(sbuf[(fakemax) - 2] == cast(char) 254);
	assert(cbuf[(fakemax) - 2] == cast(char) 254);
	assert(sbuf[(fakemax) - 1] == cast(char) 255);
	assert(cbuf[(fakemax) - 1] == cast(char) 255);
	assert(sbuf == cbuf);

}
