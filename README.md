<img src="logo.png" align="left" height="96" width="96" >

# Elembuf
An efficient and simple to use buffer/array for data manipulation.
#
[![LICENSE](https://img.shields.io/github/license/Cyroxin/Elembuf)](LICENSE)
[![bench](https://img.shields.io/badge/bench-%20-brightgreen?logo=fastly)](bench)
[![wiki](https://img.shields.io/badge/wiki-Circular%20buffer-9cf?logo=Wikimedia%20Commons)](https://en.wikipedia.org/wiki/Circular_buffer)

## Description
A circular buffer can be thought of as an array that can eliminate program side copying, making data reads from sockets or other IO more efficient. The simple idea is that if elements/array items are popped/removed from the front, the free slots can be used to fill the back of the array without moving the existing data. A simple way to understand the concept is that a circular buffer is a faster concatenator (concat/cat/~) as all free data reserves are more easily taken advantage of before needing to reallocate. Some buffers are limited to a maximum size for performance reasons, making them unalike to concat.

Elembuf is an implementation of a circular buffer. It is however different from a regular circular buffer in that it is as compact as an array, infact it is indistinquishable from a regular dynamic array and it can even be directly cast to it. Allocated memory of an Elembuf is internally memory mapped to work like a mirror of itself and it achieves higher speeds by being allocated to a custom memory position. The mirroring properties of the implementation give additional benefits to encryption and compression algorithms. You may however use Elembuf for any purpose which a regular array is used for, such as when parsing data, reading files or assembling data. Elembuf has a page sized or larger maximum array length and works directly with the OS, thus it does not use the garbage collector.

Because construction speed is slightly slower than with a regular array, reusage is key to the function of an Elembuf. You should construct the buffer at the start of the program, or at server boot, and change the source where data is received instead of deconstructing the array/buffer. This way you can take advantage of the filling speed compared to a normal array. 

Elembuf currently works for Windows, Linux, Mac and other Posix compatible systems. 


## Getting Started

For examples  on how to use the library, the documentation is a good place to start: 
* [buffer](https://cyroxin.github.io/Elembuf/buffer.html) <br />
* [source](https://cyroxin.github.io/Elembuf/source.html)

<b>Windows/Mac</b>
You can download the repo and open the solution file in the repository called "Elembuf.sln" (VS17 & VS19) with [visuald](https://github.com/dlang/visuald) in visual studio. The source files should automatically link and you may easily edit the source code and add your own code into the solution.

<b>Linux</b>
Manual linking must be done using the instructions of your own compiler. 

You may use the source files as is, regardless of what os, editor or IDE you use, as long as you know how to link
them through your compiler. If you have any questions, issues or feature requests, please create an issue on this repository.

## Contributions

Feel free to contribute by sending a pull request or sending in bug reports through issues. If you wish to help, you can assist in making the buffer callable from the C language. Remember to include tests in your pull requests!

## Maintainers

* **Cyroxin** - [Cyroxin](https://github.com/cyroxin)

