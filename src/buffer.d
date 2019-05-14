module buffer;


/// Creates a file in memory. See Linux manpages for further information. 
private version (CRuntime_Glibc) extern (C) int memfd_create(const char* name, uint flags) @nogc; // TODO: Add to druntime
/***********************************
	* Dynamic buffer with a maximum length of one page ("buf.max").
	* Takes an advantage of the system's memory mirroring capabillities to
	* create a memory loop so that memory copying wont be necessary.
	* The buffer may be manipulated normally as if it were a T[].
	* Usage:
	* ---
	* StaticBuffer!int buf = StaticBuffer!int(); 
	* ---
	* or
	* ---
	* auto buf = StaticBuffer!()(); // Underlying type defaults to char.
	* ---
	*
	* Note:
	*
	*				Setting the buffer to anything else than its own slice will
	*				cause memory leaks and break the mirroring system. Use buffer.fill() to extend the buffer.
	*
	*				<font color="blue">[WINDOWS]</font> Only one active (non-destroyed) buffer of this type is allowed per process.
	*				A new buffer will overwrite the old data and desync the old buffer.
	*				Ensure that CreateFileMapping(INVALID_HANDLE_VALUE, ...) is not used elsewhere
	*				in the application.
	* Params:
	*			T	= Element type which the buffer will hold. Defaults to char.
	*/


@nogc
struct StaticBuffer(T = char)
{

	import std.math : log2;

	alias buf this;

	/// Underlying buffer which the object manages. Avoid using this directly.
	/// Can be used to avoid safety overhead when popping items using slicing. 
	T[] buf = void;

	static assert(typeof(this).sizeof == (T[]).sizeof);

	///
	unittest
	{
		import buffer, source; // @suppress(dscanner.suspicious.local_imports)

		auto buffer = StaticBuffer!()();
		assert(buffer[0..0] == buffer.buf[0..0]);

		buffer = buffer.ptr[0 .. "Hello World!".length]; // Will not use the GC.
		buffer.fill("Hello World!");
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

	/// Number of bits that the buffer can write to. Used for bit shifts.
	static enum pagebits = cast(size_t) log2(pagesize);

	/// Maximum amount of items if buffer were a T[]. 
	/// This is very usefull if the buffer is set to be a void[] internally.
	/// Use this instead of pagesize if possible.
	static enum max = pagesize / T.sizeof;

	void opAssign()(const scope T[] newbuf) nothrow @nogc @trusted // @suppress(dscanner.style.undocumented_declaration)
	{
		assert(newbuf.ptr >= buf.ptr && newbuf.ptr <= buf.ptr); // Make sure that this is a slice.

		if ((cast(size_t) buf.ptr & pagesize) == (cast(size_t) newbuf.ptr & pagesize)) // Cost: 8%, (~7╬╝)
			buf = cast(T[]) newbuf;
		else
			buf = cast(T[])(newbuf.ptr - pagesize)[0 .. newbuf.length];

		// If the buffer pointer moves to a new page, then go back to our page
		// Issue with using bit AND is that it can only handle a maximum increase of one pagesize. 

		// Alternative to this would be a right shift followed by a left shift (lin 12/win 16),
		// which identifies the page accurately.
		// Right shift has a slight performance hit compared to AND (2-3╬╝ win@64bit - A8-6410).

		// Another alternative would be allocating a  pointer, this was avoided to keep the struct small.
		// You would essentially check if the new pointer is equal or above the second page buffer start. Perf not checked.

		// TODO: Look into if this could be done in fill.
	}

	//@disable this(this);

	static typeof(this) opCall() @nogc @trusted nothrow // @suppress(dscanner.style.undocumented_declaration)
	{
		
		scope T[] ret;

		//debug import std.stdio;
		//debug writeln("Construction");

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

			scope(exit) CloseHandle(cast(void*) memfile); // This will destroy the mapfile once there are no mappings
			

			// Find a suitable large memory location in memory.
			while (true)
			{
				ret = cast(T[]) VirtualAlloc(NULL, pagesize * 2, MEM_RESERVE, PAGE_READWRITE)[0 .. 0]; // TODO: [0..0] & cast compiler optimise?

				if (ret.ptr is NULL) // Request sent too soon
					continue;

				VirtualFree(ret.ptr, 0, MEM_RELEASE);

				// Map two contiguous views to point to the memory file created earlier.
				if (!MapViewOfFileEx(cast(void*) memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, ret.ptr))
					continue;
				else if (!MapViewOfFileEx(cast(void*) memfile,
						FILE_MAP_ALL_ACCESS, 0, 0, 0, ret.ptr + pagesize))
					UnmapViewOfFile(ret.ptr);
				else
					break;
			}

		}

		else version (CRuntime_Glibc)
		{
			//pragma(msg, "CRuntime_Glibc");

			import core.sys.posix.sys.mman : mmap, PROT_NONE, PROT_READ,
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
			ret = (cast(T*) mmap(null, 2 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0))[0
				.. 0];
			assert(ret.ptr != MAP_FAILED);

			// Sub map it to two identical consecutive maps
			mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(ret.ptr + pagesize, pagesize, PROT_READ | PROT_WRITE,
					MAP_SHARED | MAP_FIXED, memfile, 0);
		}

		else version (Posix)
		{
			//pragma(msg, "Posix");

			import core.sys.posix.sys.mman : shm_open, shm_unlink, mmap,
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
			ret = cast(T[]) mmap(null, 2 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0
				.. 0];
			assert(ret.ptr != MAP_FAILED);

			// Sub map it to two identical consecutive maps
			mmap(ret.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(ret.ptr + pagesize, pagesize, PROT_READ | PROT_WRITE,
					MAP_SHARED | MAP_FIXED, memfile, 0);
		}
		
		else
			static assert(0, "Not supported");


		/* debug
		{
			// Mutate buffer
			ret = ret.ptr[0..1];
			ret[0] = cast(T) 'a';

			assert(ret[0] == 'a'); // Ensure no error/bug occurs.

			// Revert changes
			ret[0] = T.init;
			ret = ret.ptr[0..0];
		}*/
		

		assert(ret.ptr != NULL && ret.length == 0);
		return *(cast(StaticBuffer!T*) &ret);
	}

	~this() @nogc @trusted nothrow
	{
		assert(ptr !is null); // If this is hit, the destructor is called more than once.

		/* debug 
		{
			import std.stdio;

			if(ptr is null){
				debug writeln("Destruction occurred, but pointer was already null!");
				return;
			}
			else
				writeln("Destruction");
		}*/

		clear; //Set the buffer to page start so that the os unmapper will work.

		version (Windows)
		{
			import core.sys.windows.winbase : UnmapViewOfFile;

			UnmapViewOfFile(ptr);
			UnmapViewOfFile(ptr + pagesize);

			// NOTE: There is an EX unmap with priority unmap flag, 
			// but it lacks windows 7 compatibility and is thus not used.
			// Using it in the future could mean that memory is freed
			// more quickly and if a new buffer is created immediately
			// after the destruction of the old one, the new mapping is less
			// likely to have the same old memfile.
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

		assert(length == 0);
	}


	/***********************************
	* Extends the buffer with new data. This is the interface for custom sources, 
	* where data is received from a read interface. 
	* Params:
	*				source	= Object that implements the read interface. A source must implement 
	* "ptrdiff_t read(void[] arr)", where arr is the free writable area of the buffer.
	* The source should return the amount of bytes written, otherwise less than or equal to zero.
	* For examples on how to use the read interface, see 
	* <font color="blue"><a href="https://cyroxin.github.io/Elembuf/source.html">docs/source.d</a></font>
	* Returns:
	*				True: Source can be reused.
	*				False: New source should be set.
	*/
	bool fill(Source)(ref Source source) // Normal sources
	if (__traits(hasMember, Source, "read"))
	{
		// Fill the empty area of the buffer. Returns 0 if an error occurs or there is no more data.
		scope const len = source.read((buf.ptr + buf.length)[0 .. pagesize - buf.length]);

		if (len <= 0)
			return false;

		buf = buf.ptr[0 .. buf.length + len];
		return true;
	}

	///
	unittest
	{
		import buf = buffer, source; // @suppress(dscanner.suspicious.local_imports)

		auto buffer = StaticBuffer!()();
		scope src = "192.168.1.1".NetSource!();
		bool alive = true;

		while (alive)
		{
			alive = buffer.fill(src);
			buffer.clear; // Removes all elements and resets the buffer.
		}
	}

	/***********************************
	* Extends the buffer with new data. This is a method to directly write to the buffer.
	* The following must be true on function call:
	* ---
	* assert(buffer.avail >= arr.length);
	* ---
	* Params:
	*				arr	= Array source that is slicable and has a length property.
	*/
	void fill(scope const T[] arr) nothrow @nogc @trusted // Direct write
	{
		(buf.ptr + buf.length)[0 .. arr.length] = arr;
		buf = buf.ptr[0 .. buf.length + arr.length];
	}

	///
	unittest
	{
		import buffer, source; // @suppress(dscanner.suspicious.local_imports)

		auto buf = StaticBuffer!()();

		buf.fill("Hello world!");
		assert(buf == "Hello world!");

		while (buf.avail)
			buf.fill([char.init]); // buffer.fill only accepts arrays.

		assert(buf.length == buf.max);

	}

	unittest
	{
		auto buffer = StaticBuffer!()();

		assert(buffer.length == 0);
		assert(buffer.avail == pagesize);

		buffer.fill("works");
		assert(buffer == "works");
		buffer.clear;

		char[] a = cast(char[]) "12345";
		buffer.fill(a[3 .. $]);
		buffer.fill(a[2 .. 3]);
		assert(buffer == "453");
	}

	/// Sets the buffer pointer to the start of the page and sets length to zero.
	void clear() nothrow @nogc @trusted
	{
		buf = (cast(T*)((cast(size_t) buf.ptr) >> pagebits << pagebits))[0 .. 0];
	}

	/// Returns how many T's of free buffer space is available.
	size_t avail() nothrow @nogc @trusted
	{
		return max - buf.length;
	}

}
