module buffer;

/// Helper function for buffer creation. Doing everything manually is also possible.
auto create(bool Static = true, Type = char)()
{
	static if (Static)
	{
		auto buffer = StaticBuffer!Type();
		buffer.initiate();
		return buffer;
	}
	else
		static assert(0,"Dynamic buffers are not implemented yet.");
}

/// Creates a file in memory. See Linux manpages for further information. 
version (CRuntime_Glibc) extern (C) int memfd_create(const char* name, uint flags) nothrow @nogc; // TODO: Add to druntime

/**
A fixed-length buffer that takes an advantage of system memory mirroring capabillities for performance.
Buffer size is the page size on posix systems and allocation granularity on windows.
The buffer should be set to void or null before initialising.
*/
struct StaticBuffer(T)
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

	//@disable this(this); // Copies can deinitiate the buffer.

	/// Initialises the buffer. Constructor must be used before initiation.
	void initiate()
	{

		version (Windows)
		{
			pragma(msg, "Windows");
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
			pragma(msg, "CRuntime_Glibc");

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
			pragma(msg, "Posix");

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

	}

	/// Deinitialize the buffer so that the struct may be destroyed.
	void deinitiate()
	{
		flush;

		//Get base ptr from buf.ptr right shift (lin 12/win 16)

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

	/// Extends the buffer with new data. Returns false if the source is empty and fill should not be called anymore unless source changed.
	bool fill(Source)(Source source)
	{
		static if (__traits(hasMember, Source, "read") && __traits(compiles, source.read(buf)))
		{
			// Fill the empty area of the buffer. Returns 0 if an error occurs or there is no more data.
			scope const len = source.read((buf.ptr + buf.length)[0 .. pagesize - buf.length]);

			if (len <= 0)
				return false;

			buf = buf[0 .. $ + len];
			return true;

		}
		else static if (__traits(compiles, source[0 .. $]))
		{
			if (source.length > pagesize - buf.length)
			{
				(buf.ptr + buf.length)[0 .. pagesize - buf.length] = cast(T[]) source[0
						.. pagesize - buf.length];

				buf = buf[0 .. pagesize];
				return false;
			}
			else
			{
				(buf.ptr + buf.length)[0 .. source.length] = cast(T[]) source;

				buf = buf[0 .. $ + source.length];
				return true;
			}
		}
		else
			static assert(0, "Source type is not supported");

	}

	/// Sets the buffer pointer to the start of the page and sets length to zero.
	void flush()
	{
		buf = (cast(T*)((cast(size_t) buf.ptr) >> pagebits << pagebits))[0 .. 0];
	}

	unittest
	{
		scope StaticBuffer!char buffer = StaticBuffer!char();
		buffer.initiate;

		assert(buffer.length == 0);
		assert(buffer.fill("Hello World!"));
		assert(buffer.length == "Hello World!".length);

		static foreach (i; 0 .. 4)
			assert(buffer.fill("Hello world!"));

		buffer.flush();
		assert(buffer.length == 0);

		buffer.deinitiate();

	}

}
