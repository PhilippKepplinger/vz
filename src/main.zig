const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig");
const Demuxer = @import("demuxer.zig").Demuxer;
const Decoder = @import("decoder.zig").Decoder;
const FrameReader = @import("frame-reader.zig").FrameReader;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 1) {
        return error.NoFileSpecified;
    }

    // zero terminate file path
    const file_path = args[1][0.. :0];
    std.log.debug("open file: {s}", .{file_path});

    var demuxer = try Demuxer.init(file_path);
    var decoder = try Decoder.init(&demuxer);
    var reader = try FrameReader.init(&demuxer, &decoder);

    while (reader.next()) |frame| {
        _ = frame;
    } else |err| {
        if (err == error.EOF) {
            std.log.info("EOF reached", .{});
        }
    }

    demuxer.close();
}
