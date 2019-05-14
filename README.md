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

[D]
```
void main()
{
		import buffer, source;

		auto buffer = StaticBuffer!()();
		scope src = "192.168.1.1".NetSource!();
		bool alive;

		do
		{
			alive = buffer.fill(src);
			buffer.clear; // Removes all elements and resets the buffer.
		} while (alive);
}
```

For further understanding on how to use the library, the documentation containing examples is a good place to start: 
* [buffer](https://cyroxin.github.io/Elembuf/buffer.html) <br />
* [source](https://cyroxin.github.io/Elembuf/source.html)



#

<b>Windows/Mac</b>
You may open the solution file in the repository called "Elembuf.sln" (VS17 & VS19) with [visuald](https://github.com/dlang/visuald) in visual studio. The source files should automatically link and you may easily edit the source code and add your own code into the solution.

<b>Linux</b>
Manual linking must be done using the instructions of your own compiler. 

You may use the source files as is, regardless of what os, editor or IDE you use, as long as you know how to link
them through your compiler. If you have any questions, issues or feature requests, please create an issue on this repository.

## Maintainers

* **Cyroxin** - [Cyroxin](https://github.com/cyroxin)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
