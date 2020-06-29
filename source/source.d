/***********************************
* $(P Data sources that may be used with buffers instead of directly filling or using lambdas)
*
* <a href="https://cyroxin.github.io/Elembuf/index.html"><</a>
* Macros:
* SOURCE = <a href="https://cyroxin.github.io/Elembuf/source.html">docs/source</a>
* BUFFER = <a href="https://cyroxin.github.io/Elembuf/elembuf.html">docs/buffer</a>
*/

module source;



/++ $(BR) $(BIG $(B Extension Interface))

$(BIG  It is possible to have objects act as sources by inserting a lamda returning function in a struct or class.  ) $(BR) $(BR)


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

/++ $(BR) $(BIG $(B Built-in Sources ))

$(P $(BIG  There are built-in example sources, which you may use instead of directly filling using concat or lambdas.   )) $(BR) $(BR)


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

	 auto srcarr = "World".ArraySource!char;

	 buf.length = 0;
	 buf ~= srcarr;
	 assert(buf == "World");

}

/** Source which takes data from a website.
* 
* <a href="https://cyroxin.github.io/Elembuf/source.html"><</a>
*/
struct NetSource
{

	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked, SocketException;

	debug import std.socket : lastSocketError;

	private Socket sock = void;
	private bool _empty;

	/// Checks if the socket has been closed by the sender. Does not check for data based closures (html or http). 
	bool empty(){ return _empty || !sock.isAlive;}

	this(this) @disable;

	/// Creates a connection by parsing an url from a string.
	this(const char[] url) @trusted
	{

		foreach(i, c; url)
		{
			if(c == 'w' && url[i..i+4] == "www.")
			{
				scope const Address addr = getAddress(url[i..$],80)[0];

				sock = new TcpSocket(cast(Address) addr);

				assert(sock !is null && sock.isAlive);

				sock.blocking(false);

				scope const a = "GET " ~ '/' ~ " HTTP/1.1\r\n" ~ // TODO: Allow for subfolders instead of '/'
					"Host: " ~ url ~ "\r\n" ~
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

///
unittest
{
	import elembuf, source;

	auto buf = buffer("");
	auto src = "www.bing.com".NetSource;

	while(buf.length == 0)
		buf ~= src;
}



/** Source that reads from an array as if it were a true source. 
*
* <a href="https://cyroxin.github.io/Elembuf/source.html"><</a>
*/
struct ArraySource(InternalType = char) 
{
	alias T = InternalType;
	private T[] arr;

	/// Takes in the array and stores it.
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

///
unittest
{
	import elembuf, source;

	auto buf = buffer("");
	auto src = "World".ArraySource!char;

	buf ~= src;
	assert(buf == "World");
}

///
unittest
{
	import elembuf, source;

	auto buf = buffer([0]);
	auto src = ([1,2,3,4,5]).ArraySource!int;

	buf ~= src;
	assert(buf == [0,1,2,3,4,5]);
}
