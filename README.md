<img src="logo.png" align="left" height="96" width="96" >

# Elembuf
An efficient and simple to use buffer library for data manipulation.
#

## Description
Elembuf library contains memory management structures that allow for data receival while eliminating
program side copying. The library is most useful for efficient IO data parsing, but is extensible and
can work as a base for more complex structures.

Internally it is a circular buffer with system dependent memory mirroring and shared loopback mechanisms.
Usage simplicity is one of the design goals and thus the buffer seems as if it were just a regular array.
Currently it only works for Windows, Linux, Mac and other Posix compatible systems.

Work on being fully compatible with C and C++ is underway.

## Getting Started



<b>Windows/Mac</b>
You can download the repo and open the solution file in the repository called "Elembuf.sln" (VS17 & VS19) with [visuald](https://github.com/dlang/visuald) in visual studio. The source files should automatically link and you may easily edit the source code and add your own code into the solution.

<b>Linux</b>
Manual linking must be done using the instructions of your own compiler. 

You may use the source files as is, regardless of what os, editor or IDE you use, as long as you know how to link
them through your compiler. If you have any questions, issues or feature requests, please create an issue on this repository.


#

[D]
```
void main()
{
		import std.stdio;
		import buffer, source;

		StaticBuffer!char buf = "Hello World!";
		buf = buf[$..$]; // Pop all elements 

		NetSource src;

		try {src = "192.168.1.1".NetSource;} 
		catch(Exception e) { writeln("Url incorrect or network failure."); return;}

		bool alive;

		do
		{
			alive = (buf << src); // Calls buffer.fill(src)
			buf.length = 0; // Removes all elements. O(1)
		} while (alive);
}
```

For further understanding on how to use the library, the documentation containing examples is a good place to start: 
* [buffer](https://cyroxin.github.io/Elembuf/buffer.html) <br />
* [source](https://cyroxin.github.io/Elembuf/source.html)

## Maintainers

* **Cyroxin** - [Cyroxin](https://github.com/cyroxin)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
