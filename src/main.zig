const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 1) {
        return error.NoFileSpecified;
    }

    const file_path = args[1][0.. :0];
    std.log.debug("open file: {s}", .{file_path});

    const ctx = try ffmpeg.open(io, file_path);
    const video_avctx = try ffmpeg.initVideoDecoder(ctx);
    var pkt = try ffmpeg.readPacket(ctx);
    try ffmpeg.decodePacket(video_avctx, &pkt);
}
