
[![logo](logotiny.png)]()

# Elembuf
An efficient and simple to use buffer/array for data manipulation.

[![wiki](https://img.shields.io/badge/​-Circular%20buffer-9cf?logo=Wikipedia)](https://en.wikipedia.org/wiki/Circular_buffer)
[![LICENSE](https://img.shields.io/github/license/Cyroxin/Elembuf)](LICENSE)
[![bench](https://img.shields.io/badge/benchmarks-%20-brightgreen?logo=fastly)](https://github.com/Cyroxin/Elembuf#benchmarks)
[![dub](https://img.shields.io/dub/v/elembuf?color=light%20green&logoColor=light%20green)](https://code.dlang.org/packages/elembuf)
[![ci](https://travis-ci.com/Cyroxin/Elembuf.svg?branch=master)](https://travis-ci.com/github/Cyroxin/Elembuf)
[![cov](https://img.shields.io/codecov/c/github/Cyroxin/Elembuf)](https://codecov.io/gh/Cyroxin/Elembuf)



## Description
A circular buffer can be thought of as an array that can eliminate program side copying, making data reads from sockets or other IO more efficient. The simple idea is that if elements/array items are popped/removed from the front, the free slots can be used to fill the back of the array without moving the existing data. A simple way to understand the concept is that a circular buffer is a faster concatenator (concat/cat/~) as all free data reserves are more easily taken advantage of, however, circular buffers are limited to a maximum size.

Elembuf is an implementation of a circular buffer. It is however different from a regular circular buffer in that it is as compact as an array, infact it is indistinquishable from a regular dynamic array and it can even be directly cast to it. Allocated memory of an Elembuf is internally memory mapped to work like a mirror of itself and it achieves higher speeds by being allocated to a custom memory position. The mirroring properties of the implementation give additional benefits to encryption and compression algorithms. You may however use Elembuf for any purpose which a regular array is used for, such as when parsing data, reading files or assembling data. Elembuf has a page sized or larger maximum array byte length and works directly with the OS, thus it does not use the garbage collector.

Because construction speed is slightly slower than with a regular array, reusage is key to the function of an Elembuf. You should construct the buffer at the start of the program, or at server boot, and change the source where data is received instead of deconstructing the array/buffer. This way you can take advantage of the filling speed.

Elembuf currently works for Windows, Linux, Mac and other Posix compatible systems. 


## Getting Started
 
[![bench](https://img.shields.io/badge/-documentation-dimgrey?style=for-the-badge&logo=Read%20the%20Docs&logoColor=brown)](https://cyroxin.github.io/Elembuf/buffer.html)

**Windows/Mac**

You can download the repo and open the solution file in the repository called "Elembuf.sln" (VS17 & VS19) with [visuald](https://github.com/dlang/visuald) in visual studio. The source files should automatically link and you may easily edit the source code and add your own code into the solution.

**Linux**

Manual linking must be done using the instructions of your own compiler. 

You may use the source files as is, regardless of what os, editor or IDE you use, as long as you know how to link
them through your compiler. 

**Dub**

```` D
#!/usr/bin/env dub
/+ dub.sdl:
name "app"
dependency "elembuf" version="~>1.2.2"
+/

module app;

import elembuf;
import std.stdio;

void main() {
    auto bufchar = buffer(""); // char[]
    assert(bufchar == "");
  
    bufchar ~= "Hello world!"; // Does not use the GC
    bufchar.writeln;
}

````
$ dub app.d

    Hello world!

## Benchmarks

Comparing an optimized array against elembuf in concating data. 

    Windows 10 - AMD A8-6410 x64 - 4GB memory - LDC release, 100k runs.
	Bench [buffer construction + destr]:75 ╬╝s and 3 hnsecs
	Bench [buffer runtime]:167 ╬╝s and 7 hnsecs
	Bench [array construction + destr]:15 ╬╝s and 7 hnsecs
	Bench [array runtime]:185 ╬╝s and 3 hnsecs
	Reuses needed: 3
    
	Linux MX-18.3 (Linux) - AMD A8-6410 x64- 4GB memory - DMD release -nobounds, 100k runs.
	Bench [buffer construction + destr]:24 μs and 4 hnsecs
	Bench [buffer runtime]:18 μs and 9 hnsecs
	Bench [array construction + destr]:2 μs and 9 hnsecs
	Bench [array runtime]:19 μs and 3 hnsecs
	Reuses needed: 53
    
	Linux MX-18.3 (Posix) - AMD A8-6410 x64 - 4GB memory - DMD release -nobounds, 100k runs.
	Bench [buffer construction + destr]:36 μs and 3 hnsecs
	Bench [buffer runtime]:19 μs
	Bench [array construction + destr]:2 μs and 9 hnsecs
	Bench [array runtime]:19 μs and 4 hnsecs
	Reuses needed: 83
    



[![bench](https://img.shields.io/badge/-lib%20comparison-dimgrey?style=for-the-badge&logo=fastly)](https://github.com/mingwugmail/liblfdsd/blob/master/comparison/README.md)

## Contributions

Feel free to contribute by sending a pull request or sending in bug reports through issues. If you wish to help, you can look at what still needs to be done from [projects](https://github.com/Cyroxin/Elembuf/projects). Remember to include tests in your pull requests!

## Maintainers

* **Cyroxin** - [Cyroxin](https://github.com/cyroxin)

