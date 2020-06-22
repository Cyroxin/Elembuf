/**
* <a href="https://cyroxin.github.io/Elembuf/buffer.html"><</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/buffer.html">docs/buffer</a>
*/

module source;



/++ $(BR) $(BIG $(B Extensions - Source Interface))

$(BIG  It is possible to have objects act as sources by inserting a lamda returning function in a struct or class.  ) $(BR) $(BR)

- - -
$(BR) 
+/

unittest
{
	struct mystruct(T)
	{
		auto src()
		{
			return (T[] x) 
			{
				// Write to x
				x[] = x.init;

				// Return written count
				return x.length;
			};
		}	
	}
}

/++ $(BR) $(BIG $(B Example sources - For testing and learning purposes ))

$(BIG  There are currently two example sources, which you may use. They are not for production, but serve well for learning and debugging. Here is an example on how to use them.   ) $(BR) $(BR)

- - -
$(BR) 
+/

unittest
{
	import source;
	import elembuf;

	auto buf = buffer("");
	auto src = "www.bing.com".NetSource;

	while(buf.length == 0)
		buf ~= src;

	 bool empty = src.empty; // Indicates socket closure. Closure can occur in html or http as well, which wont be detected by this.

	 auto srcarr = "World".ArraySource!char;

	 buf.length = 0;
	 buf ~= srcarr;
	 assert(buf == "World");

}

struct NetSource
{

	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked, SocketException;

	debug import std.socket : lastSocketError;

	private Socket sock = void;
	private bool _empty;

	// Checks if the socket has been closed by the sender. Does not check for html based closures. 
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


	

	auto src()()
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



/* Source that reads from an array as if it were a true source. This is best used for debugging or testing.
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
	
	auto src()
	{
		return (T[] x)
		{
			if (arr.length > x.length)
			{
				x.ptr[0..x.length] = arr.ptr[0..x.length];
				arr = arr.ptr[x.length .. arr.length];
				return x.length;
			}
			else
			{
				x.ptr[0..arr.length] = arr.ptr[0..arr.length];
				scope(exit) arr = arr.ptr[0..0];
				return arr.length;
			}
		};
	}

}