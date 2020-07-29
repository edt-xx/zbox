const std = @import("std");
const fs = std.fs;
const os = std.os;
const io = std.io;
const mem = std.mem;
const fmt = std.fmt;

const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

usingnamespace @import("util.zig");

//! the primitive terminal module is mainly responsible for providing a simple
//! and portable interface to pseudo terminal IO and control primitives to
//! higher level modules. You probably shouldn't be using this directly from
//! application code.

/// Input events
pub const Event = union(enum) {
    tick,
    escape,
    up,
    down,
    left,
    right,
    other: []const u8,
};

pub const SGR = packed struct {
    bold: bool = false,
    underline: bool = false,
    reverse: bool = false,
    fg_black: bool = false,
    bg_black: bool = false,
    fg_red: bool = false,
    bg_red: bool = false,
    fg_green: bool = false,
    bg_green: bool = false,
    fg_yellow: bool = false,
    bg_yellow: bool = false,
    fg_blue: bool = false,
    bg_blue: bool = false,
    fg_magenta: bool = false,
    bg_magenta: bool = false,
    fg_cyan: bool = false,
    bg_cyan: bool = false,
    fg_white: bool = false,
    bg_white: bool = false,

    // not
    pub fn invert(self: SGR) SGR {
        var other = SGR{};
        inline for (@typeInfo(SGR).Struct.fields) |field| {
            @field(other, field.name) = !@field(self, field.name);
        }
        return other;
    }
    // and
    pub fn intersect(self: SGR, other: SGR) SGR {
        var new = SGR{};
        inline for (@typeInfo(SGR).Struct.fields) |field| {
            @field(new, field.name) =
                @field(self, field.name) and @field(other, field.name);
        }
        return new;
    }
    // or
    pub fn unify(self: SGR, other: SGR) SGR {
        var new = SGR{};
        inline for (@typeInfo(SGR).Struct.fields) |field| {
            @field(new, field.name) =
                @field(self, field.name) or @field(other, field.name);
        }
        return new;
    }
    pub fn eql(self: SGR, other: SGR) bool {
        inline for (@typeInfo(SGR).Struct.fields) |field| {
            if (!(@field(self, field.name) == @field(other, field.name)))
                return false;
        }
        return true;
    }
};

pub const InTty = fs.File.Reader;
pub const OutTty = fs.File.Writer;

pub const ErrorSet = struct {
    pub const BufWrite = ArrayList(u8).Writer.Error;
    pub const TtyWrite = OutTty.Error;
    pub const TtyRead = InTty.Error;
    pub const Write = ErrorSet.BufWrite || ErrorSet.TtyWrite;
    pub const Read = ErrorSet.TtyRead;
    pub const Termios = std.os.TermiosGetError || std.os.TermiosSetError;
    pub const Setup = Allocator.Error || ErrorSet.Termios || ErrorSet.TtyWrite;
};

/// write raw text to the terminal output buffer
pub fn send(seq: []const u8) ErrorSet.BufWrite!void {
    try out_buf.writer().writeAll(seq);
}

pub fn sendSGR(sgr: SGR) ErrorSet.BufWrite!void {
    try send(csi ++ "0"); // always clear
    if (sgr.bold) try send(";1");
    if (sgr.underline) try send(";4");
    if (sgr.reverse) try send(";7");
    if (sgr.fg_black) try send(";30");
    if (sgr.bg_black) try send(";40");
    if (sgr.fg_red) try send(";31");
    if (sgr.bg_red) try send(";41");
    if (sgr.fg_green) try send(";32");
    if (sgr.bg_green) try send(";42");
    if (sgr.fg_yellow) try send(";33");
    if (sgr.bg_yellow) try send(";43");
    if (sgr.fg_blue) try send(";34");
    if (sgr.bg_blue) try send(";44");
    if (sgr.fg_magenta) try send(";35");
    if (sgr.bg_magenta) try send(";45");
    if (sgr.fg_cyan) try send(";36");
    if (sgr.bg_cyan) try send(";46");
    if (sgr.fg_white) try send(";37");
    if (sgr.bg_white) try send(";74");
    try send("m");
}

/// flush the terminal output buffer to the terminal
pub fn flush() ErrorSet.TtyWrite!void {
    try out.writeAll(out_buf.items);
    out_buf.items.len = 0;
}
/// clear the entire terminal
pub fn clear() ErrorSet.BufWrite!void {
    try sequence("2J");
}

pub fn beginSync() ErrorSet.BufWrite!void {
    try send("\x1BP=1s\x1B\\");
}

pub fn endSync() ErrorSet.BufWrite!void {
    try send("\x1BP=2s\x1B\\");
}

/// provides size of screen as the bottom right most position that you can move
/// your cursor to.
const TermSize = struct { height: usize, width: usize };
pub fn size() os.UnexpectedError!TermSize {
    var winsize = mem.zeroes(os.winsize);
    const err = os.system.ioctl(in.context.handle, os.TIOCGWINSZ, @ptrToInt(&winsize));
    if (os.errno(err) == 0)
        return TermSize{ .height = winsize.ws_row, .width = winsize.ws_col };
    return os.unexpectedErrno(err);
}

/// Hides cursor if visible
pub fn cursorHide() ErrorSet.BufWrite!void {
    try sequence("?25l");
}

/// Shows cursor if hidden.
pub fn cursorShow() ErrorSet.BufWrite!void {
    try sequence("?25h");
}

/// warp the cursor to the specified `row` and `col` in the current scrolling
/// region.
pub fn cursorTo(row: usize, col: usize) ErrorSet.BufWrite!void {
    assert(row > 0);
    assert(col > 0);
    try formatSequence("{};{}H", .{ row, col });
}

/// set up terminal for graphical operation
pub fn setup(alloc: *Allocator, inTty: InTty, outTty: OutTty) ErrorSet.Setup!void {
    in_buf = try ArrayList(u8).initCapacity(alloc, 4096);
    errdefer in_buf.deinit();
    out_buf = try ArrayList(u8).initCapacity(alloc, 4096);
    errdefer out_buf.deinit();

    //TODO: check that we are actually dealing with a tty here
    // and either downgrade or error
    in = inTty;
    out = outTty;

    // store current terminal settings
    // and setup the terminal for graphical IO
    var termios: os.termios = undefined;
    original_termios = try os.tcgetattr(in.context.handle);
    termios = original_termios.?;

    // termios flags for 'raw' mode.
    termios.iflag &= ~@as(
        os.tcflag_t,
        os.IGNBRK | os.BRKINT | os.PARMRK | os.ISTRIP |
        os.INLCR | os.IGNCR | os.ICRNL | os.IXON,
    );
    termios.lflag &= ~@as(
        os.tcflag_t,
        os.ICANON | os.ECHO | os.ECHONL | os.IEXTEN | os.ISIG,
    );
    termios.oflag &= ~@as(os.tcflag_t, os.OPOST);
    termios.cflag &= ~@as(os.tcflag_t, os.CSIZE | os.PARENB);

    termios.cflag |= os.CS8;

    termios.cc[VMIN] = 0; // read can timeout before any data is actually written; async timer
    termios.cc[VTIME] = 1; // 1/10th of a second

    try os.tcsetattr(in.context.handle, .FLUSH, termios);
    errdefer if (original_termios) |otermios| {
        os.tcsetattr(in.context.handle, .FLUSH, otermios) catch {};
    };

    try enterAltScreen();
    errdefer exitAltScreen() catch unreachable;

    try truncMode();
    try overwriteMode();
    try keypadMode();
    try cursorTo(1, 1);
    try flush();
}

/// generate a terminal/job control signals with certain hotkeys
/// Ctrl-C, Ctrl-Z, Ctrl-S, etc
pub fn handleSignalInput() ErrorSet.Termios!void {
    var termios = try os.tcgetattr(in.context.handle);

    termios.lflag |= os.ISIG;

    try os.tcsetattr(in.context.handle, .FLUSH, termios);
}

/// treat terminal/job control hotkeys as normal input
/// Ctrl-C, Ctrl-Z, Ctrl-S, etc
pub fn ignoreSignalInput() ErrorSet.Termios!void {
    var termios = try os.tcgetattr(in.context.handle);

    termios.lflag &= ~@as(os.tcflag_t, os.ISIG);

    try os.tcsetattr(in.context.handle, .FLUSH, termios);
}

/// restore as much of the terminals's original state as possible
pub fn teardown() void {
    if (original_termios) |otermios| {
        os.tcsetattr(in.context.handle, .FLUSH, otermios) catch {};
    }

    exitAltScreen() catch {};
    flush() catch {};

    in_buf.deinit();
    out_buf.deinit();
}

/// read next message from the tty and parse it. takes
/// special action for certain events
pub fn nextEvent() (Allocator.Error || ErrorSet.TtyRead)!?Event {
    const max_bytes = 4096;
    var total_bytes: usize = 0;

    while (true) {
        try in_buf.resize(total_bytes + max_bytes);
        const bytes_read = try in.context.read(in_buf.items[total_bytes .. max_bytes + total_bytes]);
        total_bytes += bytes_read;

        if (bytes_read < max_bytes) {
            in_buf.items.len = total_bytes;
            break;
        }
    }
    const event = parseEvent();
    debug("event: {}", .{event});
    return event;
}

// internals ///////////////////////////////////////////////////////////////////
var in: InTty = undefined;
var out: OutTty = undefined;

var in_buf: ArrayList(u8) = undefined;
var out_buf: ArrayList(u8) = undefined;

var original_termios: ?os.termios = null;

fn parseEvent() ?Event {
    const data = in_buf.items;
    const eql = std.mem.eql;

    if (data.len == 0) return Event.tick;

    if (eql(u8, data, "\x1B"))
        return Event.escape
    else if (eql(u8, data, "\x1B[A") or eql(u8, data, "\x1BOA"))
        return Event.up
    else if (eql(u8, data, "\x1B[B") or eql(u8, data, "\x1BOB"))
        return Event.down
    else if (eql(u8, data, "\x1B[C") or eql(u8, data, "\x1BOC"))
        return Event.right
    else if (eql(u8, data, "\x1B[D") or eql(u8, data, "\x1BOD"))
        return Event.left
    else
        return Event{ .other = data };
}

// terminal mode setting functions. ////////////////////////////////////////////

/// sending text to the terminal at a specific offset overwrites preexisting text
/// in this mode.
fn overwriteMode() ErrorSet.BufWrite!void {
    try sequence("4l");
}

/// sending text to the terminat at a specific offset pushes preexisting text to
/// the right of the the line in this mode
fn insertMode() ErrorSet.BufWrite!void {
    try sequence("4h");
}

/// when the cursor, or text being moved by insertion reaches the last column on
/// the terminal in this mode, it moves to the next like
fn wrapMode() ErrorSet.BufWrite!void {
    try sequence("?7h");
}
/// when the cursor reaches the last column on the terminal in this mode, it
/// stops, and further writing changes the contents of the final column in place.
/// when text being pushed by insertion reaches the final column, it is pushed
/// out of the terminal buffer and lost.
fn truncMode() ErrorSet.BufWrite!void {
    try sequence("?7l");
}

/// not entirely sure what this does, but it is something about changing the
/// sequences generated by certain types of input, and is usually called when
/// initializing the terminal for 'non-cannonical' input.
fn keypadMode() ErrorSet.BufWrite!void {
    try sequence("?1h");
    try send("\x1B=");
}

// saves the cursor and then sends a couple of version of the altscreen
// sequence
// this allows you to restore the contents of the display by calling
// exitAltScreeen() later when the program is exiting.
fn enterAltScreen() ErrorSet.BufWrite!void {
    try sequence("s");
    try sequence("?47h");
    try sequence("?1049h");
}

// restores the cursor and then sends a couple version sof the exit_altscreen
// sequence.
fn exitAltScreen() ErrorSet.BufWrite!void {
    try sequence("u");
    try sequence("?47l");
    try sequence("?1049l");
}

// escape sequence construction and printing ///////////////////////////////////
const csi = "\x1B[";

fn sequence(comptime seq: []const u8) ErrorSet.BufWrite!void {
    try send(csi ++ seq);
}

fn format(comptime template: []const u8, args: anytype) ErrorSet.BufWrite!void {
    try out_buf.writer().print(template, args);
}
fn formatSequence(comptime template: []const u8, args: anytype) ErrorSet.BufWrite!void {
    try format(csi ++ template, args);
}

// TODO: these are not portable across architectures
// they should be getting pulled in from c headers or
// make it into linux/bits per architecture.
const VTIME = 5;
const VMIN = 6;

test "static anal" {
    std.meta.refAllDecls(@This());
    std.meta.refAllDecls(Event);
    std.meta.refAllDecls(SGR);
}
