const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const FrameRenderer = struct {
    pub fn init() FrameRenderer {
        return .{};
    }

    pub fn render(self: *@This(), frame: *ffmpeg.AVFrame) !void {
        // TODO
        _ = self;
        _ = frame;
    }
};
