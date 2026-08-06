const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const scaler = @import("scaler.zig");

pub const RenderMode = enum {
    GRAY,
    ASCII,
    COMIC,
};

pub const FrameRenderer = struct {
    mode: RenderMode,
    ws: std.posix.winsize = undefined,
    io: std.Io,
    writer: std.Io.File.Writer,

    pub fn init(io: std.Io, mode: RenderMode, buffer: []u8) FrameRenderer {
        var ws: std.posix.winsize = undefined;
        _ = std.os.linux.ioctl(std.posix.STDOUT_FILENO, std.os.linux.T.IOCGWINSZ, @intFromPtr(&ws));

        std.log.debug("window size: {d}x{d}", .{ ws.col, ws.row });

        return .{
            .io = io,
            .ws = ws,
            .writer = std.Io.File.stdout().writer(io, buffer),
            .mode = mode,
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

                switch (self.mode) {
                    RenderMode.GRAY => try self.renderGray(top, bottom),
                    RenderMode.COMIC => try self.renderCOMIC(top, bottom),
                    RenderMode.ASCII => try self.renderASCII(top, bottom),
                }
            }

            if (row < self.height() - 1) {
                try self.writer.interface.writeByte('\n');
            }
        }
    }

    fn renderGray(self: *@This(), top: u8, bottom: u8) !void {
        try self.writer.interface.print(
            "\x1b[38;2;{};{};{}m\x1b[48;2;{};{};{}m{u}",
            .{ top, top, top, bottom, bottom, bottom, '▀' },
        );
    }

    fn renderASCII(self: *@This(), top: u8, bottom: u8) !void {
        const level = getAvgLevel(top, bottom);
        const brightness = getReducedBrightness(level);
        const char = getChar(top, bottom, brightness);

        try self.writer.interface.print(
            "\x1b[38;2;{};{};{}m{u}",
            .{ brightness, brightness, brightness, char },
        );
    }

    fn getAvgLevel(top: u8, bottom: u8) u16 {
        return (@as(u16, top) + @as(u16, bottom)) / 2;
    }

    fn getReducedBrightness(level: u16) u8 {
        return switch (level) {
            0...31 => 32,
            32...63 => 64,
            64...95 => 96,
            96...127 => 128,
            128...159 => 160,
            160...191 => 192,
            192...223 => 224,
            else => 255,
        };
    }

    fn getChar(top: u8, bottom: u8, level: u8) u21 {
        const i = @divTrunc(level, 31) - 1;
        const veryTopHeavy = top > bottom and top - bottom > 80;
        const topHeavy = top > bottom and top - bottom > 30;
        const balanced = (top > bottom and top - bottom <= 30) or (top < bottom and bottom - top <= 30);
        const veryBottomHeavy = bottom > top and bottom - top > 80;

        if (veryTopHeavy) {
            return "`'\"^~V/TM"[i];
        } else if (topHeavy) {
            return ".-~=itfx"[i];
        } else if (balanced) {
            return "oxsz*#%@"[i];
        } else if (veryBottomHeavy) {
            return "gumwh&W8"[i];
        } else {
            return "..,_jypq"[i];
        }
    }

    fn renderCOMIC(self: *@This(), top: u8, bottom: u8) !void {
        const char = getBlockChar(top, bottom);
        try self.writer.interface.print("{u}", .{char});
    }

    fn getBlockChar(top: u8, bottom: u8) u21 {
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
