const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const scaler = @import("scaler.zig");

pub const FrameRenderer = struct {
    ws: std.posix.winsize = undefined,
    io: std.Io,
    writer: std.Io.File.Writer,

    pub fn init(io: std.Io, buffer: []u8) FrameRenderer {
        var ws: std.posix.winsize = undefined;
        _ = std.os.linux.ioctl(std.posix.STDOUT_FILENO, std.os.linux.T.IOCGWINSZ, @intFromPtr(&ws));

        std.log.debug("window size: {d}x{d}", .{ ws.col, ws.row });

        return .{
            .io = io,
            .ws = ws,
            .writer = std.Io.File.stdout().writer(io, buffer),
        };
    }

    pub fn width(self: *@This()) u16 {
        return self.ws.col;
    }

    pub fn height(self: *@This()) u16 {
        return self.ws.row;
    }

    pub fn render(self: *@This(), frame: *ffmpeg.AVFrame) !void {
        try self.toHome();

        const pixels = frame.data[0];
        const linesize: usize = @intCast(frame.linesize[0]);

        const terminalHeight: usize = @as(u64, @intCast(frame.height)) / 2;
        for (0..terminalHeight) |row| {
            for (0..@intCast(frame.width)) |col| {
                if (col >= self.width()) {
                    continue;
                }
                const top = pixels[2 * row * linesize + col];
                const bottom = pixels[(2 * row + 1) * linesize + col];
                const char = getChar(top, bottom);

                try self.writer.interface.print("{u}", .{char});
            }

            if (row < self.height() - 1) {
                try self.writer.interface.writeByte('\n');
            }
        }
    }

    fn getChar(top: u8, bottom: u8) u21 {
        const topLevel = brightnessLevel(top);
        const bottomLevel = brightnessLevel(bottom);

        if (topLevel == bottomLevel) {
            return switch (topLevel) {
                0 => ' ',
                1 => '░',
                2 => '▒',
                else => '█',
            };
        }

        if (topLevel > bottomLevel) {
            if (topLevel == 3 and bottomLevel >= 2) {
                return '▓';
            } else {
                return '▀';
            }
        }

        if (bottomLevel == 3 and topLevel >= 2) {
            return '▓';
        }

        return '▄';
    }

    fn brightnessLevel(value: u8) u8 {
        return switch (value) {
            0...63 => 0,
            64...127 => 1,
            128...191 => 2,
            else => 3,
        };
    }

    pub fn clear(self: *@This()) !void {
        try self.writer.interface.writeAll("\x1b[2J");
    }

    pub fn writeCharAt(self: *@This(), char: u8, row: usize, col: usize) !void {
        try self.moveTo(row, col);
        try self.writer.interface.writeByte(char);
    }

    fn toHome(self: *@This()) !void {
        try self.writer.interface.writeAll("\x1b[H");
    }

    fn moveTo(self: *@This(), row: usize, col: usize) !void {
        try self.writer.interface.print("\x1b[{};{}H", .{ row + 1, col + 1 });
    }
};
