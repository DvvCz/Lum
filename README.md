# Lum

This is a simple, statically-typed language written in Lua, inspired by languages like Rust, Zig and Lua itself.

It currently compiles to these languages: ([You can find planned targets here](https://github.com/DvvCz/simplj/issues/3))
* `Lua`

It also has an interpreter for its compile time evaluator.

### Why?

There's a severe lack of competition for a streamlined language that can compile / transpile to several targets.

The current biggest language for this case is [Haxe](https://github.com/HaxeFoundation/haxe). But many targets are slow and unmaintained, due to the compiler not being bootstrapped.

### Example?

This isn't quite functional but is a preview of what the language should look like.

```rs
// `const` means "compile time", not immutability.
const intrinsics = import("intrinsics")

const fn Printer(T: type) {
	return struct {
		field: T
	}
}

const Printer = Printer(integer)
let x = Printer {}
```

### Why lua?

Luajit is fast enough, and works really well for writing small code, especially for parsing. (The parser and tokenizer are <500 lines of code!). It will eventually be bootstrapped.

### Status?

This language isn't quite ready yet. It needs a standard library, online repl, and documentation..
Come back later!