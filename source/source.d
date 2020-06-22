/**
* <a href="https://cyroxin.github.io/Elembuf/buffer.html"><</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/buffer.html">docs/buffer</a>
*/

module source;


/***********************************
* Downloads data from a specified ip address or link. Does not properly check for validity of the address.
* Examples:
* ---
* "www.bing.com".NetSource;
* ---
* - - - 
*/
struct NetSource
{

	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked, SocketException;

	debug import std.socket : lastSocketError;

	private Socket sock = void;
	private bool _empty;

	/** Checks if the socket has been closed by the sender. Does not check for html based closures. */
	bool empty(){ return _empty || !sock.isAlive;}

	this(this) @disable;

	// Creates a connection by parsing an ip or url from a string.
	this(const char[] ip) @trusted
	{

		foreach(i, c; ip)
		{
			if(c == 'w' && ip[i..i+4] == "www.")
			{
				scope const Address addr = getAddress(ip[i..$],80)[0];

				sock = new TcpSocket(cast(Address) addr);

				assert(sock !is null && sock.isAlive);

				sock.blocking(false);

				scope const a = "GET " ~ '/' ~ " HTTP/1.1\r\n" ~ // TODO: Allow for subfolders instead of '/'
					"Host: " ~ ip ~ "\r\n" ~
					"Accept: text/html, text/plain" ~ "\r\n\r\n"; 

				sock.send(a);

				return;
			}
		}

		assert(0, "Error, url invalid.");



	}

	~this() @trusted
	{
		if (sock !is null && sock.isAlive) // This is false if construction failed.
			//sock.shutdown(SocketShutdown.BOTH); // Optional, but can be thought of as common courtesy.
			sock.close;
	}


	/**
	Read interface implementation example. 

	NetSource depicts a great example on implementing a source.

	The first parameter must be a T[] for the Source to work for all buffers. Other parameters must be optional.
	As seen from the example, NetSource only works when the underlying buffer is a char[].
	

	---
	auto src()
	{
		return (char[] x) 
		{
			auto len = sock.receive(x);

			if (len < 0)
			{
				if (wouldHaveBlocked)
				{
					return 0;
				}
				else
				{
					_empty = true;
					return 0;
				}
			}
			else
			{
				return len;
			}
		};
	}
	---
	*/

	auto src()() @nogc
	{
		return (char[] x) 
		{
			auto len = sock.receive(x);

			if (len < 0)
			{
				if (wouldHaveBlocked)
				{
					return 0;
				}
				else
				{
					_empty = true;
					return 0;
				}
			}
			else
			{
				return len;
			}
		};
	}



}



/** Source that reads from an array as if it were a true source. This is best used for debugging or testing.
* Examples:
* ---
* "World".ArraySource!char;
* ([0,1,2,3,4,5]).ArraySource!int;
* ---
* - - - 
*/
struct ArraySource(InternalType = char) 
{
	alias T = InternalType;
	private T[] arr;

	this()(T[] array) @nogc
	{
		arr = cast(T[]) array;
	}

	this(Range)(Range r) @nogc
	{
		arr = cast(T[]) r;
	}

	/**
	* Read interface implementation example. 
	* 
	* This is what is currently inside ArraySource. It is a simple example of implementing a source.
	* The source has a simple T[] called arr as an internal variable, which it pops whenever the source is read.
	* 
	* Array source works for all buffers of type T[].
	* 
	* ---
	*auto src()
	{
		return (T[] x)
		{
			if (arr.length > x.length)
			{
				x[] = arr.ptr[0..x.length];
				arr = arr.ptr[x.length .. arr.length];
				return x.length;
			}
			else
			{
				x[0..arr.length] = arr.ptr[0..arr.length];
				scope(exit) arr = arr.ptr[0..0]; // It is safe to not reset, as it cannot be reused.
				return arr.length;
			}
		};
	}
	*---
	*/
	auto src()
	{
		return (T[] x)
		{
			if (arr.length > x.length)
			{
				x[] = arr.ptr[0..x.length];
				arr = arr.ptr[x.length .. arr.length];
				return x.length;
			}
			else
			{
				x[0..arr.length] = arr.ptr[0..arr.length];
				scope(exit) arr = arr.ptr[0..0]; // It is safe to not reset, as it cannot be reused.
				return arr.length;
			}
		};
	}

}