module buffer;

/// Creates a file in memory. See Linux manpages for further information. 
version (CRuntime_Glibc) extern (C) int memfd_create(const char* name, uint flags) nothrow @nogc; // TODO: Add to druntime

/**
A fixed-length buffer that takes an advantage of system memory mirroring capabillities for performance.
Buffer size is the page size on posix systems and allocation granularity on windows.
*/
struct StaticBuffer(T = char)
{
	import std.math : log2;

	alias buf this;
	

	/// Underlying buffer which the object manages. Avoid using it directly.
	T[] buf = void;

	/// Number of bytes per page of memory. Maximum bits the buffer will use.
	version (Windows) enum pagesize = 65_536;
	else version (CRuntime_Glibc)
		enum pagesize = 4096; // @suppress(dscanner.style.undocumented_declaration)
	else version (Posix)
		enum pagesize = 4096; // @suppress(dscanner.style.undocumented_declaration)
	else
		static assert(0, "System not supported!");

	/// Maximum amount of items if buffer were a T[].
	static enum max(T) = pagesize / T.sizeof;

	/// Number of bits that the buffer can write to. Used for bit shifts.
	static enum pagebits = cast(size_t) log2(pagesize);

	void opAssign()(const scope T[] newbuf) pure nothrow @nogc // @suppress(dscanner.style.undocumented_declaration)
	{
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
	}

	//@disable this(this); // Copies can deinitiate the buffer. The developer is trusted not to allow this.

	static auto opCall()
	{
		typeof(this) buf = void;

		version (Windows)
		{
			//pragma(msg, "Windows");

			import core.sys.windows.winbase : CreateFileMapping, VirtualAlloc, VirtualFree, MapViewOfFileEx, UnmapViewOfFile, CloseHandle, INVALID_HANDLE_VALUE, FILE_MAP_ALL_ACCESS;
			import core.sys.windows.windef : MEM_RELEASE, MEM_RESERVE, PAGE_READWRITE, NULL;

			// Create a file in memory, which we read using two pagesize buffers that are next to each other.
			scope const void* memfile = CreateFileMapping(INVALID_HANDLE_VALUE,
														  NULL, PAGE_READWRITE, 0, pagesize, NULL);

			// Find a suitable large memory location in memory.
			while (true)
			{
				buf = cast(T[]) VirtualAlloc(NULL, pagesize * 2, MEM_RESERVE, PAGE_READWRITE)[0 .. 0]; // TODO: [0..0] & cast compiler optimise?
				VirtualFree(buf.ptr, 0, MEM_RELEASE);

				// Map two contiguous views to point to the memory file created earlier.
				if (!MapViewOfFileEx(cast(void*)memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, buf.ptr))
					continue;
				else if (!MapViewOfFileEx(cast(void*)memfile, FILE_MAP_ALL_ACCESS, 0, 0,
										  0, buf.ptr + pagesize))
					UnmapViewOfFile(buf.ptr);
				else
					break;
			}

			CloseHandle(cast(void*)memfile);

		}

		else version (CRuntime_Glibc)
		{
			//pragma(msg, "CRuntime_Glibc");

			import core.sys.posix.sys.mman : mmap, PROT_NONE, PROT_READ,
				PROT_WRITE, MAP_PRIVATE, MAP_SHARED, MAP_FIXED, MAP_FAILED,
				MAP_ANON;
			import core.sys.posix.unistd : ftruncate;

			// Memfd_create file descriptors are automatically collected once references are dropped,
			// so there is no need to have a memfile global.

			scope const int memfile = memfd_create("test", 0);
			assert(memfile >= 0); // Errors: NoMem / MaxMemFiles

			ftruncate(memfile, pagesize);

			// Create a two page size memory mapping of the file
			buf = (cast(T*) mmap(null, 2 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0))[0
					.. 0];
			assert(buf.ptr != MAP_FAILED);

			// Sub map it to two identical consecutive maps
			mmap(buf.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(buf.ptr + pagesize, pagesize, PROT_READ | PROT_WRITE,
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

			enum iname = cast(char[]) "/simpleio-";
			char[] hname = iname ~ char.init;
			int memfile = void;

			for (; !memfile; {
				hname[$ - 1] = hname[$ - 1]++;
				if (hname[$ - 1] == char.max)
				{
					hname[$ - iname.length .. $] = char.init;
					hname.length++;
				}
			}) /+ Memory allocation +/

				// Create a memory file
				memfile = shm_open(hname.ptr, O_RDWR | O_CREAT | O_EXCL, S_IWUSR | S_IRUSR);

			scope (exit)
				close(memfile); // Deallocates memory once all mappings are unmapped

			shm_unlink(hname.ptr);
			ftruncate(memfile, pagesize); // Sets the memory file length

			// Create a two page size memory mapping of the file
			buf = cast(T[]) mmap(null, 2 * pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0)[0
					.. 0];
			assert(buf.ptr != MAP_FAILED);

			// Sub map it to two identical consecutive maps
			mmap(buf.ptr, pagesize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, memfile, 0);
			mmap(buf.ptr + pagesize, pagesize, PROT_READ | PROT_WRITE,
				 MAP_SHARED | MAP_FIXED, memfile, 0);
		}
		else
			static assert(0, "Not supported");

		assert(buf.length == 0);
		return buf;
	}

	/***********************************
	* Deinitializes the buffer so that the struct may be destroyed.
	*/
	~this()
	{
		clear; //Set the buffer to page start.

		version (Windows)
		{
			import core.sys.windows.winbase : CloseHandle, UnmapViewOfFile;

			UnmapViewOfFile(buf.ptr);
			UnmapViewOfFile(buf.ptr + pagesize);
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

		assert(buf.length == 0);
	}

	/***********************************
	* Extends the buffer with new data. Returns true if source can be reused, false otherwise.
	* Params:
	*				Source	= Array source that is slicable and has a length property.
	*/
	bool fill(Source)(Source source)
		if (__traits(hasMember, Source, "read") && __traits(compiles, source.read(buf)))
		{
			// Fill the empty area of the buffer. Returns 0 if an error occurs or there is no more data.
			scope const len = source.read((buf.ptr + buf.length)[0 .. pagesize - buf.length]);

			if (len <= 0)
				return false;

			buf = buf[0 .. $ + len];
			return true;
		}


	/***********************************
	* Extends the buffer with new data. Returns true if source can be reused, false otherwise.
	* Params:
	*	!	bool	Mutate	= Remove source array items once they have been read.
	*				Source	= Array source that is slicable and has a length property.
	*/
	bool fill(Source, bool Mutate = false)(ref Source source) pure nothrow @nogc @trusted
		if (__traits(compiles,this = source[0..$]))
		{
			if(avail > source.length) // Source fits to the buffer
			{
				(buf.ptr + buf.length)[0 .. source.length] = source;
				buf = buf.ptr[0..buf.length+source.length];

				static if(Mutate) // Mutate source option
					source = source.ptr[0..0];

				return false;
			}
			else
			{
				(buf.ptr + buf.length)[0 .. avail] = source[0 .. avail];
				buf = buf.ptr[0..buf.length+avail];

				static if(Mutate) // Mutate source option
					source = source.ptr[0..source.length-avail];

				return true;
			}
		}


	unittest 
	{
		auto buffer = StaticBuffer!()();

		assert(buffer.fill("Hello World"));
		assert(buffer.length == "Hello World".length);

		buffer = buffer.ptr[0..pagesize - 1];
		assert(!buffer.fill("Hello World"));
		assert(buffer.length == pagesize);

		buffer.length -= 6;
		string a = "Hello World";
		buffer.fill(a,true);
		assert(a == "World");



	}

	/// Sets the buffer pointer to the start of the page and sets length to zero.
	void clear() pure nothrow @nogc @trusted
	{
		buf = (cast(T*)((cast(size_t) buf.ptr) >> pagebits << pagebits))[0 .. 0];
	}

	/// Returns how much free buffer space is available.
	size_t avail() pure nothrow @nogc @trusted
	{
		return pagesize - buf.length;
	}


	unittest
	{
		auto buffer = StaticBuffer!()();

		assert(buffer.length == 0);
		assert(buffer.fill("Hello World!"));
		assert(buffer.length == "Hello World!".length);

		static foreach (i; 0 .. 4)
			assert(buffer.fill("Hello world!"));

		buffer.flush();
		assert(buffer.length == 0);

	}

}
