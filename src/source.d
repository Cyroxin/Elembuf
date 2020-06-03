module source;

/// Downloads data from a specified ip address or link. Does not check for validity of the address.
/// When the source blocks, a custom delegate defined in the compile time parameter will be called.
struct NetSource
{
	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked, SocketException;

	debug import std.socket : lastSocketError;

	private Socket sock = void;
	private bool _empty;

	/// Checks if our socket has been closed by the sender. Does not check for html closures.
	@property empty(){ return _empty ||
		!sock.isAlive;}

	this(this) @disable;

	/// Creates a connection by parsing an ip or url from a string.
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

	/**
	Read interface implementation example. 

	This is what is currently inside NetSource. 
	Parameter x must be a T[] for the Source to work for all buffers.
	As seen from the example, NetSource only works when the underlying buffer is a char[]
	=> T == char.

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
	**/



}



/// Source that reads from an array as if it were a true source. This is best used only for debugging or testing.
struct ArraySource(InternalType = char) 
{
	alias T = InternalType;
	T[] arr;

	this()(T[] array) @nogc
	{
		arr = cast(T[]) array;
	}

	this(Range)(Range r) @nogc
	{
		arr = cast(T[]) r;
	}

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



	/**
	Read interface implementation example. 

	This is what is currently inside ArraySource. 
	Array source works for all buffers of type T[].

	---
	auto src()
	{
		return (T[] x)
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
	---
	**/

}