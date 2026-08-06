const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const Demuxer = @import("demuxer.zig").Demuxer;
const Decoder = @import("decoder.zig").Decoder;
const FrameReader = @import("reader.zig").FrameReader;
const FrameScaler = @import("scaler.zig").FrameScaler;
const renderer = @import("renderer.zig");
const FrameRenderer = renderer.FrameRenderer;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    if (args.len <= 1) {
        return error.NoFileSpecified;
    }

    // zero terminate file path
    const file_path = args[args.len - 1][0.. :0];
    std.log.debug("open file: {s}", .{file_path});

    var renderBuffer: [512]u8 = undefined;
    const renderMode = getMode(args);

    var demuxer = try Demuxer.init(file_path);
    var decoder = try Decoder.init(&demuxer);
    var reader = try FrameReader.init(&demuxer, &decoder);
    var frameRenderer = FrameRenderer.init(init.io, renderMode, renderBuffer[0..]);
    var scaler = try FrameScaler.init(
        decoder.videoInfo.codec,
        frameRenderer.width(),
        frameRenderer.height() * 2, // use twice the height because terminal cells are twice as higher than wide
        ffmpeg.AV_PIX_FMT_GRAY8,
    );

    try frameRenderer.clear();

    while (reader.next()) |frame| {
        if (frame.width > 0) { // video frame
            const scaledFrame = try scaler.scale(frame);
            try frameRenderer.render(scaledFrame);
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

fn getMode(args: []const [:0]const u8) renderer.RenderMode {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "-m")) {
            if (std.mem.eql(u8, args[i + 1], "0")) return renderer.RenderMode.ASCII;
            if (std.mem.eql(u8, args[i + 1], "1")) return renderer.RenderMode.GRAY;
            if (std.mem.eql(u8, args[i + 1], "2")) return renderer.RenderMode.COMIC;
        }
    }

    return renderer.RenderMode.ASCII;
}
