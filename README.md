`??????`

This is a simple, statically-typed language written in Lua, inspired by languages like Rust, Zig and Lua itself.

It currently compiles to these languages:
* `Lua`
* ~~`JVM` (Not quite implemented)~~

### Why lua?

Luajit is fast enough, and works really well for writing small code, especially for parsing. (The parser and tokenizer are <500 lines of code!). It will eventually be bootstrapped.

### Example?

```rs
	// Hello, world!
	let x = 5 + -2 * 2
	let y = "dd" + "xyssz"

	fn test(x: int, y: string, z: float) {
	}

	if true {
		test(5, "", 3.14)
	} else if false {
		let x = 4.2 + 3.2
	} else {
		// std::print("Hello, world!") (Not implemented yet!)
	}

	while true && true {
		let x = 22
		let dd = "fffff"
		x = 55
	}
```

This language isn't quite ready yet. It needs a standard library, online repl, and a name..
Come back later!