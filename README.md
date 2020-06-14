# zbox

A very minimal terminal UI library inspired by termbox. This exists primarily
as a UI library for a separate text editor project. Still very rough.

see [examples](examples) for sample usage

![invaderdemo](examples/invader-zig.gif)

* exposes some primitives for terminal setup/control
* exposes an interface to terminal printing/drawing that de-duplicates and
batches operations sent to the terminal.
* create and manipulate offscreen cell buffers with drawing and printing
primitives, compose them, and 'push' them out to the terminal.
* Simple input events

Differences:

* Zig (possible C-API eventually)
* Prefer lack of features to external dependencies (no terminfo/termcap). 
Portability is arrived at by minimizing the interface to terminal primitives
to the most portable subset.
* input handling follows the above statement. different terminals communicate
hotkey modifiers differently. I hope to eventually support Ctrl as a modifier
portably and consistently, but currently do not. Mouse input will probably 
never be supported.
Parsing most input is currently the responsibility of the user.
* Currently no style or color support implemented, but this is planned.
* event handling should be compatible with zig's async IO. As such, this
intentionally avoids poll/signal handlers, and so `sigwinch` (terminal window
resize signal) is not used for window resizing.