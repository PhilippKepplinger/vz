const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const Demuxer = @import("demuxer.zig").Demuxer;
const Decoder = @import("decoder.zig").Decoder;
const FrameReader = @import("reader.zig").FrameReader;
const FrameScaler = @import("scaler.zig").FrameScaler;
const FrameRenderer = @import("renderer.zig").FrameRenderer;

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

    var renderBuffer: [512]u8 = undefined;
    var demuxer = try Demuxer.init(file_path);
    var decoder = try Decoder.init(&demuxer);
    var reader = try FrameReader.init(&demuxer, &decoder);
    var renderer = FrameRenderer.init(init.io, renderBuffer[0..]);
    var scaler = try FrameScaler.init(
        decoder.videoInfo.codec,
        renderer.width(),
        renderer.height() * 2, // use twice the height because terminal cells are twice as higher than wide
        ffmpeg.AV_PIX_FMT_GRAY8,
    );

    try renderer.clear();

    while (reader.next()) |frame| {
        if (frame.width > 0) { // video frame
            const scaledFrame = try scaler.scale(frame);
            try renderer.render(scaledFrame);
        } else {
            // TODO audio frame
        }
    } else |err| {
        if (err == error.EOF) {
            std.log.info("EOF reached", .{});
        }
    }

    demuxer.close();
}
