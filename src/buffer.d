/**
* <a href="https://cyroxin.github.io/Elembuf/source.html">&#11148;</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/buffer.html">docs/buffer</a>
*/

module buffer;


private version (linux)
{
	import core.stdc.config : c_long;
	extern (C) c_long syscall (c_long SYS, ...) @nogc nothrow;

	// Creates a file in memory. See Linux manpages for further information. 
	extern (C) int memfd_create(const char* name, uint flags) nothrow @trusted @nogc // TODO: Add to druntime
	{
		version(X86_64)
			return cast(int) syscall(319, name, flags);
		version(X86)
			return cast(int) syscall(356, name, flags);
	}

}




/***********************************
* Dynamic buffer with a maximum length of one memory page which can take up to <a href="#Buffer.max">max</a> elements.
* Takes an advantage of the system's memory mirroring capabillities to
* create a memory loop so that memory copying wont be necessary.
* The buffer may be manipulated normally as if it were a T[].
*
* Params:
*			InternalType= Element type which the buffer will hold. 
*			Threaded	= Create a background thread to fill the buffer. Makes it no longer directly castable to T[].
* Bugs:
*				- Setting the buffer to anything else than memory that the buffer owns will cause an exception.
*				- <b style="color:blue;">[WINDOWS]</b> Only one instance of this type, or any type that creates a file in memory, is allowed.
* $(BR)
* - - -
*
*/


struct Buffer(InternalType = char, bool Threaded = false)
{

	


	alias T = InternalType;

	static T[] gen() @trusted
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
				if (!MapViewOfFileEx(cast(void*) memfile, FILE_MAP_ALL_ACCESS, 0, 0, 0, ret.ptr))
					continue;
				else if (!MapViewOfFileEx(cast(void*) memfile,FILE_MAP_ALL_ACCESS, 0, 0, 0, cast(void*)((cast(ptrdiff_t)ret.ptr) + pagesize)))
					UnmapViewOfFile(cast(void*) ret.ptr);
				else
					break;
			} while(true);

			CloseHandle(cast(void*) memfile); // This will destroy the mapfile once there are no mappings


		}


		else version (linux)
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


	static typeof(this) opCall()
	{
		mixin("typeof(this) val = void; val.buf = typeof(this).gen();");

		static if(Threaded)
		{
			import std.parallelism : taskPool, task;

			taskPool.put(task!initWriter(val.buf.ptr,&mail));
			//return mixin("cast(typeof(this)) {typeof(this).gen(),0}");
			//return mixin(typeof(this)~" val = {"~ typeof(this) ~ ".gen(),0}; val.initWriter(val.ptr); val");
			//return cast(typeof(this)) null;
		}

			return val;
			//return mixin("cast(typeof(this)) {typeof(this).gen()};");
			//return mixin(typeof(this)~" val = {"~ typeof(this) ~ ".gen(),0}; val");
		
	}



	static typeof(this) opCall(scope const T[] init)
	{
		mixin("typeof(this) val = void; val.buf = typeof(this).gen(); val.ptr[0..init.length] = init[]; val.length = init.length;");

		static if(Threaded)
		{
			import std.parallelism : taskPool, task;

			taskPool.put(task!initWriter(val.buf.ptr,&mail));
		}

		return val;

	}



	/// Number of bytes per page of memory. Use max!T instead.
	version (Windows)
		private enum pagesize = 65_536; // This is actually allocation granularity, memory maps must be power of this.
	else {
		import core.memory : minimumPageSize;
		private enum pagesize = minimumPageSize; // Other platforms do not have allocation granularity, but only pagesize.
	}

	// Page bit or pagesize in WINDOWS: xxxx ... xxx1 0000 0000 0000 0000
	// Page bit or pagesize in LINUX: xxxx ... xxx1 0000 0000 0000
	// Page bits in WINDOWS: xxxx ... 1111 1111 1111 1111
	// Page bits in LINUX: xxxx ... 1111 1111 1111


	private enum pagebits = pagesize - 1;  // Returns the bits that the buffer can write to.
	private enum membits = -pagesize; // Returns the bits that signify the page position.

	nothrow @nogc @trusted @property void length(size_t len) {buf = buf.ptr[0..len];} // Overidden so that it can be @nogc
	nothrow @nogc @trusted @property const length() {return buf.length;} // Necessary if previous line is added.

	enum max = pagesize / T.sizeof; /// Returns the maximum size of the buffer depending on the size of T.
	nothrow @nogc @trusted @property const avail() { return max - buf.length;} // Returns how many T's of free buffer space is available. 



	T[] buf = void;
	alias buf this;

	static if (Threaded)
	{
		__gshared ptrdiff_t mail = 0; // Thread sync variable, must fit a pointer.

		static if(max <= byte.max)
			alias mailmintype = byte;
		else static if(max <= short.max)
			alias mailmintype = short;
		else static if(max <= int.max)
			alias mailmintype = int;
		else
			alias mailmintype = typeof(mail);
	}
	else
		static assert(typeof(this).sizeof == (T[]).sizeof);

	~this() @nogc @trusted nothrow
	{

		assert(buf.ptr != null);  // If this is hit, the destructor is called more than once. Performance decreases if true, but will run in release. 

		static if(Threaded) this.fill = cast(size_t delegate(T[])) null; // Shorthand for terminate worker thread

		version (Windows)
			static assert((cast(ptrdiff_t) 0xFFFF0045 & (membits & (~pagesize))) == 0xFFFE0000);
		version (linux)
			static assert((cast(ptrdiff_t) 0xFFFFF045 & (membits & (~pagesize))) == 0xFFFFE000);

		//Set the buffer to page start so that the os unmapper will work. TODO: Check if some OS can do this for us.
		buf = (cast(T*)(cast(ptrdiff_t) buf.ptr & (membits & (~pagesize))))[0..buf.length];


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
		buf = (cast(T*) newbuf.ptr) [0..newbuf.length];
	}

	/***********************************
	* Extends the buffer with new data directly from an array or buffer masquerading as an array. 
	* In this variant of fill, consuming the source is not needed nor is returning lifetime.
	* The following must be true on function call:
	* ---
	* assert(buffer.avail >= arr.length);
	* ---
	* Params:
	*		isSafe = Safety guarantee optimization, set to true if pop count after last unsafe fill is less than max or less than 2 times max after construction. 
	* Safety guaranteed calls can be stacked, but a singular call is more efficient. Removes all overhead from the buffer compared to a normal array.
	*		arr	= Array source that is slicable and has a length property.
	*/

	static if(!Threaded)
	public void fill(bool isSafe = false)(scope const T[] arr) // Direct write
		if (!Threaded)
		{
			assert(arr.length <= this.avail,"[SAFE] Not enough space available to fill the buffer");

			static if(!isSafe) buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize)) [0 .. buf.length]; // Safety not guaranteed by caller.

			(cast(T*)((cast(ptrdiff_t)buf.ptr) + buf.length)) [0 .. arr.length] = arr[];
			buf = (cast(T*)(buf.ptr))[0 .. buf.length + arr.length];
		}


	/***********************************
	* Extends the buffer with new data from an abstacted reference source.
	* Params:
	*				isSafe = Safety guarantee optimization, set to true if pop count after last unsafe fill is less or equal to max or less than 2 times max after construction. 
	* Safety guaranteed calls can be stacked, but a singular call is more efficient. Removes all overhead from the buffer compared to a normal array. 
	*				source	= Object that implements the $(SOURCE) src interface.
	* A source is valid if it implements  $(D_INLINECODE $(BLUE size_t delegate)(T[]) src()) function, where T[] is the area to be filled. 
	* The src function returns the source delegate/function, which returns the amount of elements written to the given T[].
	* See_also: Source examples at $(SOURCE)
	*/

	static if(!Threaded)
	public void fill(bool isSafe = false, Source)(ref Source source) // Attributes defined lower
		if(!Threaded)
		{
			static if(!isSafe) buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0 .. buf.length];

			scope ptrdiff_t len = void;

			// Fill the empty area of the buffer. Returns less than 0 if source is dead. Otherwise read amount.
			static if(__traits(compiles, cast(ptrdiff_t) source(T[].init)))
				len = source((cast(T*)((cast(ptrdiff_t)buf.ptr)+buf.length))[0..avail]); // source direct
			else static if(__traits(compiles, cast(ptrdiff_t) source.src()(T[].init))) // source.src
				len = source.src()((cast(T*)((cast(ptrdiff_t)buf.ptr)+buf.length))[0..avail]);
			else static assert(0, "Source interface not defined. See documentation for information.");
			

			assert(len <= this.max);

			buf = (cast(T*)(buf.ptr))[0 .. buf.length + len];

		}

	/***********************************
	* Sets the source which the buffer uses to fill itself. A subsequent call without params is needed
	* to query the background thread for new data.
	* Params:
	*				source	= Object that implements the $(SOURCE) src interface.
	* A source is valid if it implements $(D_INLINECODE $(BLUE size_t delegate)(T[]) src()) function, where T[] is the area to be filled. 
	* The src function returns the source delegate/function, which returns the amount of elements written to the given T[].
	* See_also: Source examples at $(SOURCE)
	*/

	static if(Threaded)
		public void fill()(scope const size_t delegate(T[]) source) @property // Change source
			if(Threaded)
		{
			import core.atomic;

			(*cast(mailmintype*) &mail).atomicStore!(MemoryOrder.raw)(cast(mailmintype)max + 1); // Alert thread
			while ((*cast(mailmintype*) &mail).atomicLoad!(MemoryOrder.raw)() == cast(mailmintype) max + 1){} // Wait till thread ready

			mail.atomicStore(cast(typeof(mail)) &source); // Give source to thread
			while (mail.atomicLoad!(MemoryOrder.raw) == cast(typeof(mail)) &source){} // Wait till thread ready
		}


	static if(Threaded)
		public void fill()(size_t function(T[]) source) // Change source
			if(Threaded)
			{
				import std.functional : toDelegate;
				fill(source.toDelegate);
			}


	/***********************************
	* Extends buffer by the amount of data read by the buffer and orders buffer to read additional data from the same source. 
	* Params:
	*				isSafe = Safety guarantee optimization, set to true if pop count after last unsafe fill is less or equal to max or less than 2 times max after construction. 
	* Safety guaranteed calls can be stacked, but a singular call is more efficient.
	*/

	static if(Threaded)
		public void fill(bool isSafe = false)()  @nogc nothrow
			if(Threaded)
		{
			import core.atomic : atomicLoad, atomicStore, cas, MemoryOrder;
			debug import std.math : abs;

			assert(buf.length <= max, "Error! Buffer length exceeds capacity or popped when no length");

			scope const i = atomicLoad!(MemoryOrder.raw)(*cast(mailmintype*) &mail);

			if(i > 0) {
				atomicStore!(MemoryOrder.raw)(*cast(mailmintype*) &mail,cast(mailmintype)-(i+length)); // Aquire more length
				
				static if(isSafe)
					buf = buf.ptr[0..buf.length + i];
				else
					buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0..buf.length + i];
			}
			else if(!cas!(MemoryOrder.raw, MemoryOrder.raw)(cast(mailmintype*) &mail,cast(mailmintype)i,cast(mailmintype) -length)){
				scope const x = atomicLoad!(MemoryOrder.raw)(*cast(mailmintype*) &mail);
					atomicStore!(MemoryOrder.raw)(*cast(mailmintype*) &mail,cast(mailmintype)-(x+length)); 
					
					static if(isSafe)
						buf = buf.ptr[0..buf.length + i];
					else
						buf = (cast(T*)((cast(ptrdiff_t)buf.ptr) & ~pagesize))[0..buf.length + i];
				}
			
		}


	// Concurrent background thread
		private static void initWriter()(scope const T* ptr, scope const typeof(mail)* mailptr)
			if(Threaded)
		{
				import core.atomic;

			// Alternative method: Pops = -(previousLenAsNegative - currentLenAsNegative); => source(pops);
				

				scope size_t delegate(T[]) source = (T[] x) {return 0;};
				scope T* localbuf = cast(T*) ptr;



				while(true)
				{
					// Read mail
					scope const typeof(mail) i = atomicLoad!(MemoryOrder.raw)(*cast(mailmintype*)mailptr);

					
					debug {
						import std.stdio : writeln;
						scope(failure)
						{
							debug writeln("ERROR! THREAD EXITED WITHOUT AGREEMENT WITH MAIN THREAD! ", i);
						}
					}
					

					// Got buffer length
					if(cast(mailmintype) i <= 0 && cast(mailmintype) i != -max) // New length received!
					{
						// Works as i is negative.
						scope const read = source(localbuf[0..(max+i)]);
						assert(read <= max);


						if(read == 0)
							continue;

						// Write amount read to mail so that it may be extended to buffer with call to fill()
						if(atomicExchange!(MemoryOrder.raw)(cast(mailmintype*) &mail, cast(mailmintype) read) == cast(mailmintype) max + 1)
						{

							// Order received while writing to mail
							while(atomicLoad!(MemoryOrder.raw)(*cast(mailmintype*) &mail) == cast(mailmintype) read){}
							source = *cast(typeof(source)*) atomicLoad!(MemoryOrder.raw)(mail);
							atomicStore!(MemoryOrder.raw)(mail,0); // Assume max data must be read and clear bits

							if(source == null) 
								return; // Order received to terminate.
						}
						else
							localbuf = (cast(T*)((cast(ptrdiff_t)localbuf + read) & ~pagesize));
					}
					else if(i == cast(mailmintype) max + 1) // Order received
					{
						atomicStore!(MemoryOrder.raw)(*cast(mailmintype*) &mail, cast(mailmintype) -max);
						while(atomicLoad!(MemoryOrder.raw)(*cast(mailmintype*) &mail) == cast(mailmintype) -max){}
						source = *cast(typeof(source)*) atomicLoad!(MemoryOrder.raw)(mail);
						atomicStore!(MemoryOrder.raw)(mail,0); // Assume max data must be read and clear bits


						if(source == null) 
							return; // Order received to terminate.
					}

				} // While

		} //Function
	
	


	


		



		public void opBinary(string op : "<<", T)(ref T rhs) 
		{
			fill(rhs);
		}

		public void opBinary(string op : "<<", T)(T rhs)
		{
			fill(rhs);
		}


		public void opOpAssign(string op : "<<", T)(ref T rhs)
		{
			fill!(true)(rhs);
		}

		public void opOpAssign(string op : "<<", T)(T rhs)
		{
			fill!(true)(rhs);
		}



		unittest {
			Buffer!char buf = "Hello World!";
			assert(buf.length == "Hello World!".length);

			assert(buf[$/2..$].length == "World!".length);

			buf.length = "Hello World".length;
			assert(buf == "Hello World");

			buf.length = "Hello".length;
			assert(buf == "Hello");
		}



	}

/// Construction
unittest
{
	import buffer;

	scope bufchar = Buffer!()(); // Create buffer, defaults to char[]
	assert(bufchar == "");

	scope Buffer!int bufint = Buffer!int(); // Create buffer of int[]
	assert(bufint == []);

	// With fill, internally calls constructor and then fill()

	scope Buffer!char fakebufchar = "Hello World!";
	assert(fakebufchar.avail == fakebufchar.max - "Hello World!".length);

	scope Buffer!int fakebufint = [1,2,3,4,5];
	assert(fakebufint.avail == fakebufint.max - ([1,2,3,4,5]).length);		

	scope Buffer!char fakebufcharlong = Buffer!char("Hello World!");
	assert(fakebufcharlong.avail == fakebufcharlong.max - "Hello World!".length);

	scope Buffer!int fakebufintlong = Buffer!int([1,2,3,4,5]);
	assert(fakebufintlong.avail == fakebufintlong.max - ([1,2,3,4,5]).length);	
}


/// Usage
unittest 
{
	// [BASIC]
	import buffer,source;

	Buffer!char buf = Buffer!()();

	// Sources could also directly use a delegate lambda => "(char[] x){return numberOfElementsWrittenToXArray}"
	auto srcworld = " World".ArraySource!char;
	auto srcbuf = "buf".ArraySource!char;

	buf.fill("Hello"); // Old method of filling without abstraction
	assert(buf == "Hello");

	buf.fill(srcworld); // Old method of filling with abstraction
	assert(buf == "Hello World");

	buf << " -Elem"; // Modern way of filling, equivalent to .fill
	assert(buf == "Hello World -Elem");

	buf <<= srcbuf; // Modern way of filling, equivalent to .fill!true
	assert(buf == "Hello World -Elembuf");

	buf.length = 0; // Remove all items. O(1)
	assert(buf == "" && buf.ptr[0..5] == "Hello"); // Elements are not truly gone until overwritten.

	// Sources should not output anything as they are used. Reusable sources can be implemented with a lambda.
	buf << srcworld;
	buf <<= srcbuf;

	assert(buf == ""); // Previous source reads did not output to buf as they were empty.
}


/// Optimization
unittest
{
	// [INTERMEDIATE]
	// Removing all overhead from fill by using compile-time guarantees by counting increments to slice pointer.  

	import buffer;

	char[] data(size_t characters) pure nothrow @trusted
	{
		char[] arr;
		arr.reserve(characters);
		arr.length = characters;

		arr[] = ' ';
		return arr;
	}

	Buffer!char buf = Buffer!()(); /// There is (max * 2 - 1) of free pops after construction and max after fill.

	// max * 2 - 1 pops left

	buf <<= data(buf.max); // '=' signifies unsafe fill. it is proven safe in this example
	buf = buf[$ .. $]; // Do work

	assert(buf == "");

	// max - 1 pops left

	assert(buf.avail - 1 == buf.max - 1);

	buf <<= data(buf.avail - 1); // In this case, (avail - 1) == (max - 1)
	buf = buf[$ .. $]; // We've now used our pops => 0 pops available

	assert(buf == "");

	// Out of free pops after construction. Next pop to an unsafely filled buffer will cause an exception eventually.
	// From this point on, every safe fill will set max to available pops

	buf << data(0); // Safety is now reinstated by the buffer. => Max pops available
	assert(buf == ""); // While there are max pops available, there is nothing to pop

	buf <<= "a";
	buf <<= data(buf.max-1);

	assert(buf[0] == 'a');
	buf = buf [$..$]; // We've now used our pops => 0 pops available

	// Note: Changing length does not add to the pop count.

	buf << data(buf.max);
	buf.length = buf.max/2; // Setting length is @nogc in a buffer
	buf <<= data(buf.max/2); // We still have max pops.

	buf = buf [$..$]; // We've now used our pops => 0 pops available

}



/// Properties
unittest
{
	// [ADVANCED]
	// This is a example of how to mirror data to create new array item orders using a mirror.
	// X will represent max/2 amount of data that is viewed by the buffer and O data that is not viewed, but still owned by it.
	// | will represent the mirror or page boundary. Left side of | is reality and right side is the mirror image.

	// OO|OO => First O is identical to third O & Second O is identical to fourth O.
	// XX|OO Length is max.
	// OX|OO max/2 is popped
	// OX|XO Length is max => Data order is now reversed, First is the second half of max/2 and then is the first half.
	// Example on how to do this:

	import buffer;

	Buffer!char buf = Buffer!()(); // OO|OO
	buf.length = buf.max; // XX|OO

	buf = buf[buf.max/2..$]; // OX|OO
	buf[] = 'a'; // Set all in X to 'a' => 0a|0a
	buf.length = buf.max; // OX|XO
	buf[$/2..$] = 'b'; // Set all X right side of | to 'b' => ba|ba

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
			private enum pagesize = 65_536; // This is actually allocation granularity, memory maps must be power of this.
		else {
			import core.memory : minimumPageSize;
			private enum pagesize = minimumPageSize; // Other platforms do not have allocation granularity, but only pagesize.
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

		Buffer!char sbuf = "";
		StaticCopyBuffer!char cbuf = "";

		sbuf.fill(data(fakemax));
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

		sbuf.fill(data(fakemax/2));
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
