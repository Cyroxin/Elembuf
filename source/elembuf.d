/***********************************
* $(P Optimized containers alike to arrays)
*
*
* <a href="https://cyroxin.github.io/Elembuf/index.html"><</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/elembuf.html">docs/buffer</a>
*/

module elembuf;

import std.traits : isArray;

/++ $(BR) $(P $(BIG $(B Whole library can be used in 5 lines. No new methods to remember while beating the efficiency of arrays and queues.))) $(BR) $(BR) +/
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

$(P $(BIG  No outdated push/pop methods. IO libraries that require pointers work out of the box. Just use a lambda. )) $(BR) $(BR)


$(BR) 
+/
unittest
{
	// Construct
	auto buf = buffer([1,2,3]);

	auto src = (int[] arr)
	{ 
		arr[0] = 4;
		return 1;
	};

	// Fill
	buf ~= src;
	assert(buf == [1,2,3,4]);

	// Reuse
	buf.length = 0;
	buf ~= src;
	buf ~= 5;
	assert(buf == [4,5]);
} 


/++ $(BR) $(BIG $(B Concurrency - Built in for your convenience))

$(P $(BIG  Simple solution for single consumer-producer synchronization that works efficiently in the background without mutexes or slow synchronization keywords.)) $(BR) $(BR)


$(BR) 
+/
unittest
{
	alias T = size_t; 

	// Producer thread created
	auto buf = tbuffer((T[]).init); 

	size_t counter;

	size_t delegate(T[]) source = (T[] arr)
	{ 
			foreach(ref i; arr)
			{
				i = counter;
				counter++;
			}

		return arr.length;
	};

	// Give instructions to producer
	buf ~= source; 


	for(int i; i < buf.max * 5; )
	{
		while(buf.length == 0)
		{
			// Aquire data
			buf ~= buf.source; 
		}

		i += buf.length;
		buf = buf[$..$];
	}

	// Unallocate all data &
	// destroy the thread.
	// Can be used for all buffers.
	buf.deinit;
}


/+++

$(BR) $(BIG $(B Mirroring - For Compression & Decryption))

$(P $(BIG  New item orders can easily be established without copying using a mirror provided by the operating system. )) $(BR) $(BR)



$(BR) $(BR) $(P $(BIG Memory can be visualized as blocks of two $(BIG $(B O))'s, each having a size of $(BIG $(D_INLINECODE max/2)). The buffer only sees memory marked with $(BIG $(B X))'s. 
The mirror border is marked with $(BIG $(B |)), right side of which is the mirrored memory. ))

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
	buf = buf.ptr[ buf.max / 2 .. buf.max + buf.max / 2 ];

	// ab|ab
	assert(buf[0] == 'b');
	assert(buf[$-1] == 'a');

	/+ Order: ab -> ba +/
} 


/**
* $(P Dynamic circular array.) 
*
* $(BR) $(BR)
*
* <a href="https://cyroxin.github.io/Elembuf/elembuf.html"><</a>
*
*
$(P $(BIG  Takes an advantage of the system's memory mirroring capabillities to
* create a memory loop so that memory copying wont be necessary once new data is concatenated.
* The buffer may be manipulated normally as if it were a T[] and can be implicitly converted to it.
* Buffer length after concatenation must be less or equal to the `.max` size of the array. ))
*
* $(BR)
*
Params:
*      arg =     The initiating data for the array. If it is immutable, it is copied into a mutable buffer. An empty buffer initiation can be achieved with the `.init` of any array type.
*
* Returns:
* `buffer!(Unqual!(ForeachType!A)[], false)`
*
* Examples:
* ---
* auto buf = buffer("Hello world!");
* ---
* ---
* buffer!(char[], false) buf = "Hello world!";
* ---
* ---
* buffer!(int[], false) buf = buffer([1,2,3,4,5]);
* ---
* ---
* buffer!(ulong[], false) buf = buffer(cast(ulong[]) [1,2,3,4,5]);
* ---
*
* Bugs: 
*  $(UL $(LI $(BIG The `~=` -operator cannot be used in `@nogc` code, but it does not use the GC.)))
*/



auto buffer(A)(A arg)
{
	import std.traits : Unqual, ForeachType;

	return buffer!(Unqual!(ForeachType!A)[], false)(arg);

}


/*****
$(P Threaded dynamic circular array.)

$(BR) $(BR) 

<a href="https://cyroxin.github.io/Elembuf/elembuf.html"><</a>


$(P $(BIG  It is a wait-free single consumer-producer threaded version of the unthreaded circular array. It achieves high throughput as it does not use mutexes or the built-in
 synchronized keyword. It however loses the ability to directly add elements to the buffer, the producer should instead be taught on how to fill the buffer using function pointers & 
 delegates.))

 $(BR)

 Params:
      arg =     The initiating data for the array. If it is immutable, it is copied into a mutable buffer. An empty buffer initiation can be achieved with the `.init` of any array type.

 Returns:
 `buffer!(Unqual!(ForeachType!A)[], true)`

Examples:
 ---
 auto buf = tbuffer("Hello world!"); 
 ---
 ---
 buffer!(char[], true) buf = "Hello world!";
 ---
 ---
 buffer!(int[], true) buf = tbuffer([1,2,3,4,5]);
 ---
 ---
 buffer!(ulong[], true) buf = tbuffer(cast(ulong[]) [1,2,3,4,5]);
 ---

 Bugs: 
  $(UL $(LI $(BIG The `~=` -operator cannot be used in `@nogc` code, but it does not use the GC.)))

 Note:
 $(P The threaded version of the buffer loses the ability to concat directly to the buffer. Instead you should teach the producer how to fill the buffer: )

 ---
 alias T = char;

 auto buf = tbuffer(T[].init);
 enum source = buf.source; 

 int i = 1;

// Teach the producer. 
// This is a delegate as it accesses i.
 buf ~= (T[] arr) 
 {
	arr[0] = T.init;
	return i;
 };

assert(buf.length == 0);

// Request data if available
 buf ~= source;

 ---
*/

auto tbuffer(A)(A arg)
{
	import std.traits : Unqual, ForeachType;

	return buffer!(Unqual!(ForeachType!A)[], true)(arg);

}

unittest{

}





private struct buffer(ArrayType, bool threaded)
if(isArray!(ArrayType))
{
	version(LDC)
		import ldc.attributes : allocSize;
	else
		struct allocSize{this(int _){}} // Needed to remove intrinsic compile-time errors. 

	import std.traits : Unqual, ForeachType;
	//debug import std.stdio : writeln;

	alias T = Unqual!(ForeachType!ArrayType);

	//pragma(msg,"root: ", threaded, " - ", ArrayType, " - ", T);

	T[] buf;
	alias buf this;

	invariant {assert(buf.length <= max);}

	static if (threaded)
		align(mail.sizeof) __gshared ptrdiff_t mail = 0; // Thread sync variable, must fit a pointer.
	else
		static assert(typeof(this).sizeof == (T[]).sizeof);

	

	this(Unqual!T[] arr) shared
	{
		//debug writeln("1 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate[0..arr.length];
		tempbuf[] = arr[];
		buf = cast(shared) tempbuf;
	}

	this(Unqual!T[] arr)
	{
		//debug writeln("3 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate[0..arr.length];
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
		T[] tempbuf = initiate[0..arr.length];
		tempbuf[] = arr[];
		buf = cast(shared) tempbuf;
	}

	this(inout Unqual!T[] arr)
	{
		//debug writeln("5 ",threaded, " - ", ArrayType.stringof, " - ", T.stringof);
		T[] tempbuf = initiate[0..arr.length];
		tempbuf[] = arr[];
		buf = tempbuf;

		static if(threaded)
		{
			import std.parallelism : taskPool, task;
			taskPool.put(task!initWriter(buf.ptr,&mail));
		}
	}

	
	static T* initiate(typeof(pagesize) _ = max*T.sizeof*2) @nogc @trusted nothrow @allocSize(0)
	{
		T* ret = void;

		version (Windows)
		{
			//pragma(msg, "Windows");

			import core.sys.windows.winbase : CreateFileMapping, VirtualAlloc,
				VirtualFree, MapViewOfFileEx, UnmapViewOfFile, CloseHandle,
				INVALID_HANDLE_VALUE, FILE_MAP_ALL_ACCESS;
			import core.sys.windows.windef : MEM_RELEASE, MEM_RESERVE, PAGE_READWRITE, NULL;

			// Create a file in memory, which we read using two pagesize buffers that are next to each other.
			scope const void* memfile = CreateFileMapping(INVALID_HANDLE_VALUE,
														  NULL, PAGE_READWRITE, 0, pagesize, NULL);

			debug
			{
				import core.sys.windows.winbase : GetLastError;
				import core.sys.windows.windef :ERROR_ALREADY_EXISTS;
				assert(GetLastError != ERROR_ALREADY_EXISTS,"[WINONLYERR] There are multiple type instances that create files to memory. Either destroy existing or use another buffer type.");
			}

			while(true)
			{
				// Find a suitable large memory location in memory. TODO: Dropping win7 compatab will allow this to be automated by the os.
				ret = cast(T*) VirtualAlloc(NULL, pagesize * 3, MEM_RESERVE, PAGE_READWRITE);
				assert(ret != NULL); // Outofmem

				// Select a page with a pagebit of 0.
				if ((cast(ptrdiff_t) ret & pagesize) == pagesize) // Pagebit 1, next is 0, final 1
				{
					ret = (cast(T*)((cast(ptrdiff_t) ret) + pagesize));
					VirtualFree(cast(void*)((cast(ptrdiff_t) ret) - pagesize), 0, MEM_RELEASE);
				}
				else // Pagebit 0, next 1, third 0
					VirtualFree(cast(void*)ret, 0, MEM_RELEASE);


				// Map two contiguous views to point to the memory file created earlier.
				if (!MapViewOfFileEx(cast(void*) memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*) ret))
					continue;
				else if (!MapViewOfFileEx(cast(void*) memfile,FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*)((cast(ptrdiff_t)ret) + pagesize)))
					UnmapViewOfFile(cast(void*) ret);
				else
					break;
			}

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
			ret =  cast(T*) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
			assert(ret != MAP_FAILED); // Outofmem

			if ((cast(ptrdiff_t)ret & pagesize) == 0) // First page is 0, second 1, third 0
			{
				// Sub map it to two identical consecutive maps
				mmap(ret, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize * 2), pagesize);
			}
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize));

				// Sub map it to two identical consecutive maps
				mmap(ret, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*) ((cast(ptrdiff_t)ret) - pagesize), pagesize);
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
			ret = cast(T*) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
			assert(ret != MAP_FAILED); // Outofmem

			if ((cast(ptrdiff_t)ret & pagesize) == 0) // First page is 0, second 1, third 0
			{
				// Sub map it to two identical consecutive maps
				mmap(ret, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize * 2), pagesize);
			}
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret) + pagesize));

				// Sub map it to two identical consecutive maps
				mmap(ret, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
				mmap(cast(T*)((cast(ptrdiff_t)ret) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);

				munmap(cast(T*) ((cast(ptrdiff_t)ret) - pagesize), pagesize);
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
		in(buf.length + rhs.length <= max,"BufErr: Not enough space available to fill the buffer. Buffer must be at most .max(), subtract .length() from this to get available space.")
		{
				buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & ~pagesize))[0 .. buf.length + rhs.length]; 
				buf[$ - rhs.length .. $] = rhs[];

		}
	public void opOpAssign(string op : "~")(inout T rhs) 
		if(!threaded)
		in(buf.length + 1 <= max,"BufErr: Not enough space available to fill the buffer. Buffer must be at most .max(), subtract .length() from this to get available space.")
		{

			buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & ~pagesize))[0 .. buf.length + 1]; 
			buf[$ - 1] = rhs;

		}
	
	public void opOpAssign(string op : "~",Source)(ref Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs(T[].init);}))
		in(rhs != null, "BufErr: new source is null! Cannot insert null source. Did you perhaps mean to use threaded buffer?")
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs(buf.ptr[buf.length .. buf.length + this.max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}

	public void opOpAssign(string op : "~",Source)(ref Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs.src()(T[].init);}))
			in(rhs.src() != cast(typeof(rhs.src())) null, "BufErr: new source is null! Cannot insert null source. Did you perhaps mean to use threaded buffer?")
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs.src()(buf.ptr[buf.length.. buf.length + this.max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}
	public shared void opOpAssign(string op : "~")(inout shared T[] rhs)
		if(!threaded)
		in(buf.length + rhs.length <= max,"BufErr: Not enough space available to fill the buffer. Buffer must be at most .max(), subtract .length() from this to get available space.")
		{
			buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & ~pagesize))[0 .. buf.length + rhs.length]; 
			buf[$ - rhs.length .. $] = rhs[];
		}
	public shared void opOpAssign(string op : "~")(inout shared T rhs) 
		if(!threaded)
		in(buf.length + 1 <= max,"BufErr: Not enough space available to fill the buffer. Buffer must be at most .max(), subtract .length() from this to get available space.")
		{
			buf = cast(shared) (cast(T*)(cast(ptrdiff_t) buf.ptr & ~pagesize))[0 .. buf.length + 1]; 
			buf[$ - 1] = rhs;

		}

	public shared void opOpAssign(string op : "~",Source)(ref Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs(T[].init);}))
			in(rhs != null, "BufErr: new source is null! Cannot insert null source. Did you perhaps mean to use threaded buffer?")
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs(buf.ptr[buf.length..buf.length + this.max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}

	public shared void opOpAssign(string op : "~",Source)(ref Source rhs)
		if(!threaded && __traits(compiles, { size_t ret = rhs.src()(T[].init);}))
			in(rhs.src() != cast(typeof(rhs.src())) null, "BufErr: new source is null! Cannot insert null source. Did you perhaps mean to use threaded buffer?")
		{

			buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope const size_t len = rhs.src()(buf.ptr[buf.length..buf.length + this.max - buf.length]);

			assert(buf.length + len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}
	public void opOpAssign(string op : "~",Source)(Source rhs)
		if(threaded) // Threaded - change source
			in(rhs != null, "ThreadedBufErr: new source is null! Cannot insert null source. You should use .source instead!")
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
			in(rhs == null && buf.length <= max, "ThreadedBufErr: Length is more than maximum or did not fill with buffer.source!")
		{
			import core.atomic : atomicLoad, atomicStore, cas, MemoryOrder;

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
	in((cast(ptrdiff_t)s.ptr & mempos) == (cast(ptrdiff_t)buf.ptr & mempos), "BufErr: Setting the buffer to another memory position is not allowed, you can only slice and set slices. ")
	{
		buf = s;
	}

	shared void opAssign(scope shared T[] s)
		in((cast(ptrdiff_t)s.ptr & mempos) == (cast(ptrdiff_t)buf.ptr & mempos), "BufErr: Setting the buffer to another memory position is not allowed, you can only slice and set slices. ")
	{
		buf = cast(shared) s;
	}

	// FUNCTIONS

	///
	nothrow @nogc @trusted @property void length(inout size_t len) in(len <= max) {buf = buf.ptr[0..len];} // Overidden so that it can be @nogc
	///
	inout nothrow @nogc @trusted @property auto length() out (ret; ret <= max) {return buf.length;}

	shared nothrow @nogc @trusted @property void length(inout size_t len) in(len <= max) {buf = buf.ptr[0..len];} // Overidden so that it can be @nogc
	inout shared nothrow @nogc @trusted @property auto length() out (ret; ret <= max) {return buf.length;}
	

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

	
	/// Maximum amount of items that the buffer can hold. Use this and length to determine how much can be concatenated.
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
				if(cast(typeof(mail)) i <= 0) // New length received!
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
					{
						localbuf += read;
						localbuf = cast(T*) (cast(ptrdiff_t) localbuf & ~pagesize);
					}
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

unittest // Anonymous linkage test
{
	// It is crucial that the buffers are not created with the same name. Preferably they should be made anonymous, but this is not possible on posix. Only Win & Lin.
	// On posix, there is a maximum buffer count which really depends on how many similarly named memory files are created. This is usually quite high.

	auto buf = buffer("");
	buf ~= 'a';

	auto buf2 = buffer("");
	buf2.length = 1;
	
	assert(buf != buf2); 
}

unittest // Concat tests
{
	auto buf = buffer("");
	auto bufptr = buf.ptr;

	buf ~= 'a';
	assert(buf.ptr == bufptr);

	shared sbuf = buffer("");
	auto sbufptr = sbuf.ptr;

	sbuf ~= 'a';
	assert(sbuf.ptr == sbufptr);
}


// Usage
unittest 
{
	import elembuf, source;
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

unittest // Pointer looparound
{
	auto buf = buffer(cast(ubyte[]) []);
	auto bufptr = buf.ptr;
	auto bufmaxptr = buf.ptr[buf.max*2..buf.max*2].ptr;
	auto src = (ubyte[] x){return x.length;};

	buf ~= src;
	buf = buf[$-1..$]; // Does not make buffer loop around
	bufptr = buf.ptr;
	assert(buf.ptr < bufmaxptr - buf.max); // In first page

	buf ~= src;
	buf = buf[$..$];
	bufptr = buf.ptr;
	assert(buf.ptr < bufmaxptr);
	assert(buf.ptr == bufmaxptr - 1); // 0xXXXX FFFF

	buf ~= src;
	assert(buf.ptr < bufmaxptr - buf.max); // In first page
	assert(buf.ptr == bufptr - buf.max); // 0xXXXX FFFF




}