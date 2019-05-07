module source;

/// Downloads data from a specified ip address or link. Does not check for validity of the address.
/// When the source blocks, a custom delegate defined in the compile time parameter will be called.
struct NetSource(alias code = {}) if (__traits(compiles, code()))
{
	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked;

	debug import std.socket : lastSocketError;

	private Socket sock = void;

	this(this) @disable;

	/// Creates a connection by parsing an ip or url from a string.
	this(const string ip) @trusted
	{
		scope const Address addr = getAddress(ip, 80)[0];
		sock = new TcpSocket(cast(Address) addr);

		assert(sock !is null && sock.isAlive);

		sock.blocking(false);

		scope const a = "GET " ~ '/' ~ " HTTP/1.1\r\n" ~ // TODO: Allow for subfolders instead of '/'
				"Host: " ~ ip ~ "\r\n" ~
				"Accept: text/html, text/plain" ~ "\r\n\r\n"; 
		
		sock.send(a);
	}

	///
	unittest {
		char[] fakebuffer = "Hello world";

		// Set fakebuffer to empty every time the source blocks.
		// A blocking source means that data has not been received yet. 
		// It is best to do productive small tasks while waiting for data.
		auto src = "127.0.0.1".NetSource!({fakebuffer.length = 0;});
	}

	~this() @trusted
	{
		assert(sock !is null && sock.isAlive);
		//sock.shutdown(SocketShutdown.BOTH); // Removed for the sake of efficiency
		sock.close;
		destroy(sock);
	}

	/// Reads new data to the buffer. Returns -1 on error, 0 on empty and positive for bytes read
	ptrdiff_t read()(void[] buf) @trusted
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
		scope len = sock.receive(buf);
		assert(len >= -1);

		while (true)
		{
			if (len < 0)
			{
				if (wouldHaveBlocked)
				{
					// Do something productive here.
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


import std.traits : isDynamicArray;

/// Source that reads from an array as if it were a true source. This is best used only for debugging or testing.
struct ArraySource(T) 
if (isDynamicArray!T)
{

	T arr;

	this(T array){
		arr = array;
	}

	/// Will never return a negative number. Zero if empty.
	ptrdiff_t read()(void[] buf) {
		if (arr.length > buf.length)
		{
			buf[0..$] = cast(void[]) arr[0..buf.length];
			arr = arr[buf.length .. $];
			return buf.length;
		}
		else
		{
			buf[0..arr.length] = cast(void[]) arr[0..arr.length];
			arr = (arr.ptr + arr.length)[0..0];
			return arr.length;
		}
		return buf.length;
	}

}