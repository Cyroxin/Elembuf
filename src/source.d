module source;

/// Downloads data from a specified ip address. Does not check for validity of the address.
/// When the source blocks, a custom delegate or function will be called.
/// Example: auto src = "127.0.0.1".NetSourceCustom!({});
struct NetSource(alias code = {  }) if (__traits(compiles, code()))
{
	import std.socket : Socket, TcpSocket, Address, getAddress,
		wouldHaveBlocked;

	debug import std.socket : lastSocketError;

	private Socket sock = void;

	/// Creates a connection by parsing an ip from a string.
	this(string ip)
	{
		scope const Address addr = getAddress(ip, 80)[0];
		sock = new TcpSocket(cast(Address) addr);

		assert(sock !is null && sock.isAlive);

		sock.blocking(false);

		sock.send(
				"GET " ~ '/' ~ " HTTP/1.1\r\n" ~ // TODO: Allow for subfolders instead of '/'
				"Host: " ~ ip ~ "\r\n"
				~ "Accept: text/html, text/plain" ~ "\r\n\r\n");
	}

	/// Disconnects the connection.
	void deinitiate()
	in
	{
		assert(sock !is null && sock.isAlive);
	}
	do
	{
		//sock.shutdown(SocketShutdown.BOTH); // Removed for the sake of efficiency
		sock.close;
	}

	/// Reads new data to the buffer. Returns -1 on error, 0 on empty and positive for bytes read
	ptrdiff_t read()(void[] buf)
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
