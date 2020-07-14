# zbox

A very minimal terminal UI library inspired by termbox. This exists primarily
as a UI library for a separate text editor project.



### Usage
see [examples](examples) for sample usage

![invaderdemo](examples/invader-zig.gif)

### Features
* exposes some primitives for terminal setup/control
* exposes an interface to terminal printing/drawing that de-duplicates and
batches operations sent to the terminal.
* create and manipulate offscreen cell buffers with drawing and printing
primitives, compose them, and 'push' them out to the terminal.
* Simple input events

### Design Philosophy and differences from termbox
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

### Portability & Stability
currently only tested on linux, but should be broadly posix compliant. Not
thoroughly tested in general, but everything seems to work in common terminals
like (ux)term, linux console, whatever crap ubuntu uses by default, kitty, and
alacritty.

Highly unlikely to work on windows given that we are not using libc (which could
do some mocking of linux syscalls related APIs on windows ala Cygwin). Planned to
at least support windows for putting the tty in raw mode, but will not translate
ANSI/VT control sequences to windows API calls. You'd have to use something like
windows terminal or mintty.

Still very rough, and probably broken in most places.