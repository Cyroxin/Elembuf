module buffer;

static import types;

// Creates a file in memory. See Linux manpages for further information. 
private version (CRuntime_Glibc) extern (C) int memfd_create(const char* name, uint flags) nothrow @trusted @nogc; // TODO: Add to druntime

/***********************************
* Dynamic buffer with a maximum length of one memory page which can take up to <a href="#StaticBuffer.max">max</a> elements.
* Takes an advantage of the system's memory mirroring capabillities to
* create a memory loop so that memory copying wont be necessary.
* The buffer may be manipulated normally as if it were a T[].
*
* Note:
*				1. Setting the buffer to anything else than memory that the buffer owns will cause memory leaks and exceptions.
*				2. <b style="color:blue;">[WINDOWS]</b> Multiple instances of this type in one process will slice the same memory.
* Params:
*			T	= Element type which the buffer will hold. Defaults to char.
*/

struct StaticBuffer(InternalType = char)
{
	alias T = InternalType;

	///
	static typeof(this) opCall() @nogc @trusted nothrow
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


			// Find a suitable large memory location in memory. TODO: Dropping win7 compatab will allow this to be automated by the os.
			while (true)
			{
				ret = cast(T[]) VirtualAlloc(NULL, pagesize * 3, MEM_RESERVE, PAGE_READWRITE)[0..0];

				// Select a page with a pagebit of 0.
				if ((cast(ptrdiff_t) ret.ptr & pagesize) == pagesize) // Pagebit 1, next is 0, final 1
				{
					ret = (cast(T*)((cast(ptrdiff_t) ret.ptr) + pagesize))[0..0];
					VirtualFree(cast(void*)((cast(ptrdiff_t) ret.ptr) - pagesize), 0, MEM_RELEASE);
				}
				else // Pagebit 0, next 1, third 0
					VirtualFree(cast(void*)ret.ptr, 0, MEM_RELEASE);


				// Map two contiguous views to point to the memory file created earlier.
				if (!MapViewOfFileEx(cast(void*) memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, ret.ptr))
					continue;
				else if (!MapViewOfFileEx(cast(void*) memfile,FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*)((cast(ptrdiff_t)ret.ptr) + pagesize)))
					UnmapViewOfFile(cast(void*) ret.ptr);
				else
				{
					CloseHandle(cast(void*) memfile); // This will destroy the mapfile once there are no mappings
					break;
				}

			}

		}

		else version (CRuntime_Glibc)
		{
			//pragma(msg, "CRuntime_Glibc");

			import core.sys.posix.sys.mman : mmap, munmap, PROT_NONE, PROT_READ,
				PROT_WRITE, MAP_PRIVATE, MAP_SHARED, MAP_FIXED, MAP_FAILED,
				MAP_ANON;
			import core.sys.posix.unistd : ftruncate, close;

			// Memfd_create file descriptors are automatically collected once references are dropped,
			// so there is no need to have a memfile global.
			scope const int memfile = memfd_create("elembuf", 0);

			if (memfile == -1)
				assert(0, "Memory file creation error!");

			//assert(memfile >= 0); // Errors: NoMem / MaxMemFiles

			ftruncate(memfile, pagesize);

			// Create a two page size memory mapping of the file
			ret =  cast(T[]) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0..0];
			assert(ret.ptr != MAP_FAILED);

			if ((cast(ptrdiff_t)ret.ptr & pagesize) == 0) // First page is 0, second 1, third 0
				munmap(ret.ptr, pagesize * 3);
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize))[0..ret.length];
				munmap(cast(T*) ((cast(ptrdiff_t)ret.ptr) - pagesize), pagesize * 3);
			}


			// Sub map it to two identical consecutive maps
			mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
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

			enum iname = cast(char[]) "/elembuf-";
			scope char[iname.length + 1] hname = iname;
			scope int memfile = void;

			static foreach (i; char.min .. char.max)
			{
				hname[$ - 1] = i;

				// Create a memory file
				memfile = shm_open(hname.ptr, O_RDWR | O_CREAT | O_EXCL, S_IWUSR | S_IRUSR);
				if (memfile >= 0)
					goto cont;

			}
			assert(0, "Memory file creation error!");

		cont:

			scope (exit)
				close(memfile); // Deallocates memory once all mappings are unmapped

			shm_unlink(hname.ptr);
			ftruncate(memfile, pagesize); // Sets the memory file length

			// Create a two page size memory mapping of the file
			ret = cast(T[]) mmap(null, 3 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0..0];
			assert(ret.ptr != MAP_FAILED);


			if ((cast(ptrdiff_t)ret.ptr & pagesize) == 0) // First page is 0, second 1, third 0
				munmap(ret.ptr, pagesize * 3);
			else // First page is 1, second 0, third 1
			{
				ret = (cast(T*)((cast(ptrdiff_t)ret.ptr) + pagesize))[0..ret.length];
				munmap(cast(T*)((cast(ptrdiff_t)ret.ptr) - pagesize), pagesize * 3);
			}


			// Sub map it to two identical consecutive maps
			mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(cast(T*) ((cast(ptrdiff_t)ret.ptr) + pagesize), pagesize, PROT_READ | PROT_WRITE,
				 MAP_SHARED | MAP_FIXED, memfile, 0);
		}

		else
			static assert(0, "Operating system not supported");



		assert(ret.ptr != NULL);

		return *cast(typeof(this)*) &ret;
	}

	///
	unittest
	{
		import buffer, source;

		scope bufchar = StaticBuffer!()(); // Create buffer, defaults to char[]
		assert(bufchar == "");

		scope StaticBuffer!int bufint = StaticBuffer!int(); // Create buffer of int[]
		assert(bufint == []);

		// With fill, internally calls constructor and then fill()

		scope StaticBuffer!char fakebufchar = "Hello World!";
		assert(fakebufchar.avail == fakebufchar.max - "Hello World!".length);

		scope StaticBuffer!int fakebufint = [1,2,3,4,5];
		assert(fakebufint.avail == fakebufint.max - ([1,2,3,4,5]).length);		

		scope StaticBuffer!char fakebufcharlong = StaticBuffer!char("Hello World!");
		assert(fakebufcharlong.avail == fakebufcharlong.max - "Hello World!".length);

		scope StaticBuffer!int fakebufintlong = StaticBuffer!int([1,2,3,4,5]);
		assert(fakebufintlong.avail == fakebufintlong.max - ([1,2,3,4,5]).length);	
	}

	static typeof(this) opCall(scope const T[] init) @nogc @trusted nothrow
	{
		auto ret = opCall();

		ret.ptr[ret.length..init.length] = init[];
		ret.buf = ret.ptr[0..ret.length + init.length];

		return ret;

	}


	/// Number of bytes per page of memory. Use max!T instead.
	version (Windows)
		private enum pagesize = 65_536;

	else version (CRuntime_Glibc)
		private enum pagesize = 4096; /// ditto

	else version (Posix)
		private enum pagesize = 4096; /// ditto

	else
		static assert(0, "System not supported!");

	// Page bit or pagesize in WINDOWS: xxxx ... xxx1 0000 0000 0000 0000
	// Page bit or pagesize in POSIX: xxxx ... xxx1 0000 0000 0000
	// Page bits in WINDOWS: xxxx ... 1111 1111 1111 1111
	// Page bits in POSIX: xxxx ... 1111 1111 1111

	private enum pagebits = pagesize - 1;  // Returns the bits that the buffer can write to.
	private enum membits = -pagebits; // Returns the bits that signify the page position.
	enum max = pagesize / T.sizeof; /// Returns the maximum size of the buffer depending on the size of T.
	nothrow @nogc @trusted size_t avail() { return max - buf.length;} /// Returns how many T's of free buffer space is available.
	nothrow @nogc @trusted @property void length(size_t len) {buf = buf[0..len];} // Overidden so that it can be @nogc
	nothrow @nogc @trusted @property size_t length() {return buf.length;} // Necessary if previous line is added.


	// Underlying type which the buffer manages, modifying this will exit out of safe mode.
	// Safe mode does not improve performance in release, but removes all debug asserts in debug mode.

	T[] buf = void;
	alias buf this;

	static assert(typeof(this).sizeof == (T[]).sizeof);

	~this() @nogc @trusted nothrow
	{
		assert(buf.ptr != null);  // If this is hit, the destructor is called more than once. Performance decreases if true, but will run in release. 

		//Set the buffer to page start so that the os unmapper will work. TODO: Check if some OS can do this for us.
		buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & (~pagebits)))[0..buf.length];


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
	
	
	void opAssign(scope const T[] newbuf) nothrow @nogc @trusted
	{
		buf = (cast(T*)(cast(ptrdiff_t) newbuf.ptr))[0..newbuf.length];
	}


	unittest 
	{
		scope StaticBuffer!char buf = StaticBuffer!()();

		// Mirroring test
		buf[buf.max] = 'a';
		assert(buf[0] == 'a');

		scope(exit) destroy!false(buf);
	}

	/***********************************
	* Extends the buffer with new data directly from an array or buffer masquerading as an array. 
	* This is the most efficient extension method as consuming the source is not needed nor is returning lifetime.
	* The following must be true on function call:
	* ---
	* assert(buffer.avail >= array.length);
	* ---
	* Params:
	*		isSafe = Safety guarantee optimization, set to true if pop count after last unsafe fill is less than max or less than 2 times max after construction. 
	* Safety guaranteed calls can be stacked, but a singular call is more efficient. Removes all overhead from the buffer compared to a normal array. <b>Default:</b> <font color=red>False.</font>
	*		array	= Array source that is slicable and has a length property.
	*/

	public void fill(bool isSafe = false, ArrayType)(ArrayType array) // Direct write
		if(!(types.isSource!(ArrayType)) && __traits(compiles, array[0..$]))
		{
			//pragma(msg, ArrayType);

			assert((max - buf.length) >= array.length, "[SAFE] Not enough space available to fill the buffer"); 
			assert(array.length <= this.max);

			static if(!isSafe) buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize)) [0 .. buf.length]; // Safety not guaranteed by caller.

			(cast(T*)((cast(ptrdiff_t)buf.ptr) + buf.length)) [0 .. array.length] = array[];
			buf = (cast(T*)(buf.ptr))[0 .. buf.length + array.length];
		}


	/***********************************
	* Extends the buffer with new data from an abstacted reference source.
	* Params:
	*				isSafe = Safety guarantee optimization, set to true if pop count after last unsafe fill is less than max or less than 2 times max after construction. 
	* Safety guaranteed calls can be stacked, but a singular call is more efficient. Removes all overhead from the buffer compared to a normal array. <b>Default:</b> <font color=red>False.</font>
	*				source	= Object that implements the <font color="blue"><a href="https://cyroxin.github.io/Elembuf/types.html">docs/types</a></font> source interface.
	* The function "ptrdiff_t read(void[] arr)" is expected to be implemented, where arr is the free writable area of the buffer.
	* It should return the amount of bytes written, otherwise less than or equal to zero.
	* For examples on how to implement the read interface, see 
	* <font color="blue"><a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a></font>
	* Returns:
	*				True: Source is not empty and can be reused.
	*				False: Source has been emptied.
	*
	*/
	
	public bool fill(bool isSafe = false, Source)(scope ref Source source) // Attributes defined lower
		if (types.isSource!(Source))
			{

				static if(!isSafe) buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

				// Fill the empty area of the buffer. Returns less than 0 or less if source is dead.
				scope const len = source.read((buf.ptr+buf.length)[0..this.avail]);

				assert(len <= this.max);

				if (len <= 0)
					return false;

				buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];
				return true;
			}

	
	/// Usage
	nothrow @nogc @trusted 
		unittest 
		{
			// [BASIC]
			import buffer,source;

			StaticBuffer!char buf = StaticBuffer!()();

			ArraySource!char srcworld = ArraySource!char(" World!");
			ArraySource!char srcbuf = ArraySource!char("buf");

			buf.fill("Hello"); // Old method of filling without abstraction
			assert(buf == "Hello");

			buf.fill(srcworld); // Old method of filling with abstraction
			assert(buf == "Hello World!");

			buf << " -Elem"; // Modern way of filling, equivalent to .fill
			assert(buf == "Hello World! -Elem");

			buf <<= srcbuf; // Modern way of filling, equivalent to .fill!true
			assert(buf == "Hello World! -Elembuf");

			buf.length = 0; // Remove all items. O(1)
			assert(buf == "" && buf[0..5] == "Hello"); // Elements are not truly gone until overwritten.

			assert((buf << srcworld) == false); // Source consumed.
			assert((buf <<= srcbuf) == false); // Source consumed.
		}

	

	/// Optimization
	unittest
	{
		// [INTERMEDIATE]
		// Removing all overhead from fill by using compile-time guarantees by counting increments to slice pointer.  

			char[] data(size_t characters) pure nothrow @trusted
			{
				char[] arr;
				arr.reserve(characters);
				arr.length = characters;

				arr[] = ' ';
				return arr;
			}

			StaticBuffer!char buf = StaticBuffer!()(); /// There is (max * 2 - 1) of free pops after construction.

			buf <<= data(buf.max);

			buf = buf[$ .. $]; // Do work
			assert(buf == "");

			// max - 1 pops left

			buf <<= data(buf.avail - 1); // In this case, (avail - 1) == (max - 1)

			buf = buf[$ .. $]; // Do work
			assert(buf == "");

			// Out of free pops. Next pop will cause an exception.

			buf << data(buf.max); // Safety is now reinstated by the buffer.
			buf = buf [$..$]; // Can now pop buf.max times again!

			// Repeat from last comment region. Note: Setting length does not add to the pop count.
		}

	
	/// Properties
	unittest
	{
		// [ADVANCED]
		// This is a example of how to mirror data to create new array element orders using a mirror.
		// X will represent data that is viewed by the buffer and O data that is not viewed, but still owned by it.
		// | will represent the mirror or page boundary. Left side of | is the first page, right side is the second.

		StaticBuffer!char buf = StaticBuffer!()(); // OO|OO
		buf.length = buf.max; // XX|OO

		buf = buf[buf.max/2..$]; // OX|OO
		buf[] = 'a'; // Set all in X to 'a'
		buf.length = buf.max; // OX|XO
		buf[$/2..$] = 'b'; // Set all X right side of | to 'b'

		// The buffer is in a mirror |, half of the buffer is in the first page and half in second page. OX|XO
		// It is possible to invert the buffer so, that data starts with 'b' instead of 'a'.
		// Data is identical left and right side of the mirror, thus inversion can be sought from the mirror.

		// a, OX|XO
		buf = (buf.ptr - buf.max/2)[0..buf.max]; // XX|OO
		assert(buf[0] == 'b' && buf[$/2+1] == 'a'); // Opt: In this case $ could be buf.max as well.

		// b, XX|OO
		buf = (buf.ptr + buf.max)[0..buf.length]; // OO|XX
		assert(buf[0] == 'b' && buf[$/2+1] == 'a'); // As seen, both sides are identical. Both pages contain a's and b's. 

	}




	

	public auto opBinary(string op : "<<", T)(ref T rhs) 
	{
		return fill(rhs);
	}

	public void opBinary(string op : "<<", T)(T rhs)
	{
		fill(rhs);
	}


	public auto opOpAssign(string op : "<<", T)(ref T rhs)
	{
		return fill!(true)(rhs);
	}

	public void opOpAssign(string op : "<<", T)(T rhs)
	{
		fill!(true)(rhs);
	}
	
	
	//  Enabling this unittest will cause socket requests every compile.
	unittest
	{
		import std.stdio;
		import buffer, source;

		StaticBuffer!char buf = "Hello World!";
		buf = buf[$..$]; // Pop all elements 

		NetSource src;

		try {src = "192.168.1.1".NetSource;} 
		catch(Exception e) { writeln("Url incorrect or network failure."); return;}

		bool alive;

		do
		{
			alive = (buf << src); // Calls buffer.fill(src)
			buf.length = 0; // Removes all elements. O(1)
		} while (alive);
	}
	
	
	
	
	unittest {
		StaticBuffer!char buf = "Hello World!";
		assert(buf.length == "Hello World!".length);
		
		assert(buf[$/2..$].length == "World!".length);
		
		buf.length = "Hello World".length;
		assert(buf == "Hello World");

		buf.length = "Hello".length;
		assert(buf == "Hello");
	}
	
	

}


/* 
 This is a conventional buffer that should not be used in applications.
 It is used purely for internal benchmarking when comparing a
 circular buffer implementation with copying buffers.
*/ 
struct StaticCopyBuffer(InternalType = char)
{
	alias T = InternalType;
	/// Number of bytes per page of memory. Use max!T instead.
	version (Windows)
		private enum pagesize = 65_536;

	else version (CRuntime_Glibc)
		private enum pagesize = 4096; /// ditto

	else version (Posix)
		private enum pagesize = 4096; /// ditto

	else
		static assert(0, "System not supported!");

	// Page bit or pagesize in WINDOWS: xxxx ... xxx1 0000 0000 0000 0000
	// Page bit or pagesize in POSIX: xxxx ... xxx1 0000 0000 0000
	// Page bits in WINDOWS: xxxx ... 1111 1111 1111 1111
	// Page bits in POSIX: xxxx ... 1111 1111 1111

	private enum pagebits = pagesize - 1;  /// Returns the bits that the buffer can write to.
	private enum membits = -pagebits; /// Returns the bits that signify the page position.
	enum max = pagesize / T.sizeof; // Returns the maximum size of the buffer depending on the size of T.
	nothrow @nogc @trusted size_t avail() { return max - buf.length;} // Returns how many T's of free buffer space is available.
	nothrow @nogc @trusted @property void length(size_t len) {buf = buf[0..len];} // Overidden so that it can be @nogc
	nothrow @nogc @trusted @property size_t length() {return buf.length;}

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

		cont:
			ret = cast(T[]) VirtualAlloc(NULL, pagesize, MEM_COMMIT, PAGE_READWRITE)[0 .. 0]; // TODO: [0..0] & cast compiler optimise?

			if (ret.ptr is NULL) // Request sent too soon
				goto cont;


		}

		else version (Posix)
		{
			//pragma(msg, "Posix");

			import core.sys.posix.sys.mman : mmap, PROT_NONE, MAP_PRIVATE, MAP_FAILED, MAP_ANON;

			ret = cast(T[]) mmap(null, pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0.. 0];
			assert(ret.ptr != MAP_FAILED);
		}

		else
			static assert(0, "Not supported");

		assert(ret.ptr != NULL && ret.length == 0);
		return *(cast(typeof(this)*) &ret);
	}

	static typeof(this) opCall(const T[] init) @nogc @trusted nothrow
	{
		auto ret = opCall();
		ret.fill(init);
		return ret;

	}


	unittest 
	{
		import buffer, source;

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

		buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & (~pagebits)))[0..buf.length]; //Set the buffer to page start so that the os unmapper will work.

		version (Windows)
		{
			import core.sys.windows.windef : MEM_RELEASE;
			import core.sys.windows.winbase : VirtualFree;

			VirtualFree(buf.ptr, 0, MEM_RELEASE);
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
		buf = (cast(T*)(cast(ptrdiff_t) newbuf.ptr))[0..newbuf.length];
	}

	bool fill(E)(scope ref E source)
		if(__traits(hasMember, E, "read"))
		{
			// Old data to start of buffer
			(cast(T*)(cast(ptrdiff_t) buf.ptr & (-pagesize)))[0..buf.length] = buf[];
			buf = (cast(T*)(cast(ptrdiff_t)buf.ptr & (-pagesize)))[0..buf.length];

			// Fill the empty area of the buffer. Returns 0 if an error occurs or there is no more data.
			scope const len = source.read((buf.ptr + buf.length)[0 .. avail(buf)]);

			if (len <= 0)
				return false;

			buf = buf.ptr[0 .. buf.length + len];
			return true;
		}


	void fill(scope const T[] arr)
	{
		assert(arr.length <= this.avail);

		// Old data to start of buffer
		(cast(T*)(cast(ptrdiff_t) buf.ptr & (-pagesize)))[0..buf.length] = buf[];
		buf = (cast(T*)(cast(ptrdiff_t)buf.ptr & (-pagesize)))[0..buf.length];

		// New data to end of buffer
		(cast(T*)((cast(ptrdiff_t)buf.ptr) + buf.length)) [0 .. arr.length] = arr[];
		buf = buf.ptr[0..buf.length + arr.length];

	}

}