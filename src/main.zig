const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig");
const Demuxer = @import("demuxer.zig").Demuxer;
const Decoder = @import("decoder.zig").Decoder;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 1) {
        return error.NoFileSpecified;
    }

    const file_path = args[1][0.. :0];
    std.log.debug("open file: {s}", .{file_path});

    var demuxer = try Demuxer.init(file_path);
    var decoder = try Decoder.init(&demuxer);

    var frame = try decoder.decodeFrame(); // TODO handle errors
    while (true) { // TODO handle EOF
        frame = try decoder.decodeFrame();
    }

    demuxer.close();
}
