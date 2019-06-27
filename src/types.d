module types;

private template hasFunc(obj, funcreturntype, string funcname, params...)
{
	// Returns true if call compiles
	private bool testFunc()
	{
		static if(!is(funcreturntype == void))
				return __traits(compiles, cast(funcreturntype) (obj o) => mixin("o." ~ funcname)(params));
		else
				return __traits(compiles,(obj o) => mixin("o." ~ funcname)(params));
	}

	enum hasFunc = 
		__traits(hasMember, obj, funcname) &&
			testFunc();

}

/***********************************
* Buffer conformance checker, will return true if object is a valid buffer.
* All of the subsequent functions may have optional arguments or alternative variants, 
* but they must be callable with just these arguments. 
* - Implements opSlice(size_t,size_t), opAssign(typeof(this)), opDollar and length.
* - Implements function "size_t avail()", returns number of available items.
* - Implements function "void fill(T[])", fills the buffer. T[] is void[] if T is not defined as an alias in the struct.
* - Implements either a function, variable or enumerator "size_t max"
*/

template isBuffer(B)
{
	static if(__traits(hasMember, B, "T") && __traits(compiles, B.T)) 
		enum init = ((B.T)[]).init;
	else
		enum init = (typeof((void*).init[0..0])).init;

	enum isBuffer = 
		hasFunc!(B,size_t, "avail") && // size_t avail
		hasFunc!(B,void, "fill",init) && // fill(T[])
		__traits(compiles, (B b) => b[5..$]) && // opSlice & opDollar
		__traits(compiles, (B b) => assert(__traits(isArithmetic, b.max))) && // max
		__traits(compiles, (B b) => assert(__traits(isArithmetic, b.length))); // length

}

/***********************************
* Source conformance checker, will return true if object is a valid source.
* - Implements "ptrdiff_t read(T[])", if "alias T = ?" is not declared in struct, T will default to void[].
*/

template isSource(S)
{
	static if(__traits(hasMember, S, "T") && __traits(compiles, S.T)) 
		enum isSource = hasFunc!(S, ptrdiff_t,"read",((S.T)[]).init);
	else
		enum isSource = hasFunc!(S, ptrdiff_t,"read",(typeof((void*).init[0..0])).init );
}

unittest 
{
	import buffer, source, types;
	enum funcname = "fun";
	alias T = char;

	struct bun {
		import std.stdio;
		void fun (int i) { writeln("Hello ",  i);}
	}

	static assert(hasFunc!(StaticBuffer!char,size_t,"avail"));
	static assert(hasFunc!(StaticBuffer!char,void,"fill",(T[]).init));

	static assert(!isSource!(typeof("Hello")));
	static assert(!isBuffer!(ArraySource!(char)));
	static assert(isSource!(ArraySource!(char)));
	static assert(isBuffer!(StaticBuffer!(char)));
}


