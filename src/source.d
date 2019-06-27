module source;

/// Downloads data from a specified ip address or link. Does not check for validity of the address.
/// When the source blocks, a custom delegate defined in the compile time parameter will be called.
struct NetSource
{
	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked, SocketException;

	debug import std.socket : lastSocketError;

	private Socket sock = void;

	this(this) @disable;

	/// Creates a connection by parsing an ip or url from a string.
	this(const string ip) @trusted
	{
		import std.stdio;
		try
		{
			scope const Address addr = getAddress(ip,80)[0];
			sock = new TcpSocket(cast(Address) addr);

			assert(sock !is null && sock.isAlive);

			sock.blocking(false);

			scope const a = "GET " ~ '/' ~ " HTTP/1.1\r\n" ~ // TODO: Allow for subfolders instead of '/'
				"Host: " ~ ip ~ "\r\n" ~
				"Accept: text/html, text/plain" ~ "\r\n\r\n"; 

			sock.send(a);
		}
		catch (SocketException e)
			writefln("  Lookup failed: %s", e.msg);

	}

	~this() @trusted
	{
		assert(sock !is null && sock.isAlive);
		//sock.shutdown(SocketShutdown.BOTH); // Optional,but can be thought of as common courtesy.
		sock.close;
	}

	/// Reads new data to buf. Returns negative on error, zero on empty and positive for bytes read
	ptrdiff_t read(alias code = {}, bool callOnce = false)(scope void[] buf) @trusted
		if (__traits(compiles, code()))
		in
		{
			assert(sock !is null && sock.isAlive);
		}
	out(ret)
	{
		assert(ret >= 0);
	}
	do
	{
		auto len = sock.receive(buf);

		static if (callOnce)
		{
			if (len < 0)
				if (wouldHaveBlocked)
				{
					code();
					len = sock.receive(buf);
				}
				else
					return 0;
			else
				return len;
		}

		while (true)
		{
			if (len < 0)
			{
				if (wouldHaveBlocked)
				{
					// Do something productive here.

					static if(!callOnce)
						code();

					len = sock.receive(buf);

				}
				else
					return 0;
			}
			else
				return len;
		}

	}
}


/// Source that reads from an array as if it were a true source. This is best used only for debugging or testing.
struct ArraySource(InternalType = char) 
{
	alias T = InternalType;
	T[] arr;

	this(T[] array) pure nothrow @nogc
	{
		arr = cast(T[]) array;
	}

	this(Range)(Range r)
	{
		arr = cast(T[]) r;
	}

	/// Will never return a negative number. Zero if empty.
	ptrdiff_t read(scope T[] buf) pure nothrow @nogc
	{

		if (arr.length > buf.length)
		{
			buf[] = arr[0..buf.length];
			arr = arr[buf.length .. $];
			return buf.length;
		}
		else
		{

			buf[0..arr.length] = arr[];
			scope(exit) arr = arr[0..0]; // It is safe to not reset, as it cannot be reused.
			return arr.length;
		}
	}

}