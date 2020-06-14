const std = @import("std");
const display = @import("zbox");
const options = @import("build_options");
const ArenaAllocator = std.heap.ArenaAllocator;
const page_allocator = std.heap.page_allocator;
const ArrayList = std.ArrayList;

pub usingnamespace @import("log_handler.zig");

const bad_char = '%';
const ship_char = '^';
const bullet_char = '.';

const bb_width = 7;
const bb_height = 3;
const baddie_block_init = [bb_height][bb_width]u8{
    .{ 1, 0, 1, 0, 1, 0, 1 },
    .{ 0, 1, 0, 1, 0, 1, 0 },
    .{ 1, 0, 1, 0, 1, 0, 1 },
};
var baddie_block = baddie_block_init;
var bb_y: usize = 1;
var bb_countdown: usize = 3;

const Bullet = struct {
    x: usize = 0,
    y: usize = 0,
};

var bullets = [_]Bullet{.{}} ** 4;
var score: usize = 0;
const width: usize = 7;
const mid_width: usize = 4;
const height: usize = 24;
const mid_height = 11;
var ship_x: usize = 4; // center of the screen.

var state: enum {
    start,
    playing,
    win,
    lose,
} = .playing;

pub fn main() !void {
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    var alloc = &arena.allocator;

    // initialize the display with stdin/out
    try display.init(
        alloc,
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );
    defer display.deinit();

    // ignore ctrl+C
    try display.ignoreSignalInput();
    try display.cursorHide();
    defer display.cursorShow() catch {};

    var game_display = try display.Buffer.init(alloc, height, width);
    var output = try display.Buffer.init(alloc, height, width);

    while (try display.nextEvent()) |e| {
        const size = try display.size();
        output.clear();
        try output.resize(size.height, size.width);

        if (size.height < height or size.width < width) {
            const row = std.math.max(1, size.height / 2);
            var cursor = output.cursorAt(row, 1);
            try cursor.writer().writeAll("display too small; resize.");
            try display.push(output);
            continue;
        }

        switch (e) {
            .left => if (ship_x > 1) {
                ship_x -= 1;
            },
            .right => if (ship_x < width) {
                ship_x += 1;
            },

            .other => |data| {
                const eql = std.mem.eql;
                if (eql(u8, " ", data)) {
                    std.log.debug(.invaders, "pyoo", .{});
                    for (bullets) |*bullet| if (bullet.y == 0) {
                        bullet.y = height - 1;
                        bullet.x = ship_x;
                        break;
                    };
                }
            },

            .escape => return,
            else => {},
        }

        game_display.clear();

        game_display.cellRef(height, ship_x).char = ship_char;

        for (bullets) |*bullet| {
            if (bullet.y > 0) bullet.y -= 1;
            if ((bullet.y == 1) and (score > 0)) {
                score -= 1;
            }
        }
        if (bb_countdown == 0) {
            bb_countdown = 6;
            bb_y += 1;
        } else bb_countdown -= 1;

        var baddie_count: usize = 0;
        for (baddie_block) |baddie_row, row_offset| for (baddie_row) |_, col_offset| {
            const row_num = row_offset + bb_y;
            const col_num = col_offset + 1;

            if (baddie_block[row_offset][col_offset] > 0) {
                if (row_num > height) { // baddie reached bottom
                    if (score >= 5) {
                        score -= 5;
                    } else {
                        score = 0;
                    }

                    continue;
                }
                for (bullets) |*bullet| {
                    if (bullet.x == col_num and
                        bullet.y <= row_num)
                    {
                        score += 3;
                        baddie_block[row_offset][col_offset] -= 1;
                        bullet.y = 0;
                        bullet.x = 0;
                    }
                }

                game_display.cellRef(row_num, col_num).char = bad_char;
                baddie_count += 1;
            }
        };

        if ((baddie_count == 0) or (bb_y > height)) {
            bb_y = 1;
            baddie_block = baddie_block_init;
            bullets = [_]Bullet{.{}} ** 4; // clear all the bullets
        }

        for (bullets) |bullet| {
            if (bullet.y > 0) game_display.cellRef(bullet.y, bullet.x).char = bullet_char;
        }
        var score_curs = game_display.cursorAt(1, 4);
        try score_curs.writer().print("{:0>4}", .{score});

        const game_row = if (size.height >= height + 2)
            size.height / 2 - mid_height
        else
            1;

        const game_col = if (size.width >= height + 2)
            size.width / 2 - mid_width
        else
            1;

        output.blit(game_display, @intCast(isize, game_row), @intCast(isize, game_col));
        try display.push(output);
    }
}
