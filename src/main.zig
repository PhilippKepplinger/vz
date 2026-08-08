const std = @import("std");
const Io = std.Io;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const mctx = @import("media-context.zig");
const Demuxer = @import("demuxer.zig").Demuxer;
const Decoder = @import("decoder.zig").Decoder;
const FrameReader = @import("reader.zig").FrameReader;
const FrameScaler = @import("scaler.zig").FrameScaler;
const renderer = @import("renderer.zig");
const FrameRenderer = renderer.FrameRenderer;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    if (args.len <= 1) {
        return error.NoFileSpecified;
    }

    // zero terminate file path
    const file_path = args[args.len - 1][0.. :0];
    std.log.debug("open file: {s}", .{file_path});

    var renderBuffer: [65535]u8 = undefined;
    const renderMode = getMode(args);

    // move all this to a player struct in the future
    var mediaCtx = try mctx.MediaContext.init(file_path);
    var demuxer = try Demuxer.init(&mediaCtx);
    var decoder = try Decoder.init(&mediaCtx);
    var reader = try FrameReader.init(&demuxer, &decoder);
    var frameRenderer = try FrameRenderer.init(io, arena, renderMode, &mediaCtx, renderBuffer[0..]);
    var scaler = try FrameScaler.init(
        decoder.videoCodec,
        frameRenderer.width(),
        frameRenderer.height() * 2, // use twice the height because terminal cells are twice as high than wide
        ffmpeg.AV_PIX_FMT_GRAY8, // maybe change in the future
    );

    try frameRenderer.clear();

    const clock = std.Io.Clock.real;
    const frameTimeNs: i96 = @divTrunc(@as(i96, @intCast(mediaCtx.videoStream.time_base.num)) * 1_000_000_000, @as(i96, @intCast(mediaCtx.videoStream.time_base.den)));
    const startTimeNs = clock.now(io).toNanoseconds();
    var currentTimeNs: i96 = 0; // current elapsed time
    var targetTimeNs: i96 = 0; // when a frame needs to be rendered

    // example:
    // time_base = 1/24000 = 0.041667 s
    // frame_time = 1/24000 * 1_000_000_000
    // pts = 1001, 2002, usw.
    // target time = pts * frame_time = 1001 / 24000

    var perfStart = clock.now(io).toMilliseconds();
    var perfDecode: i64 = 0;
    var perfScale: i64 = 0;
    var perfRender: i64 = 0;

    // render pipeline
    while (reader.next()) |frame| {
        perfDecode = clock.now(io).toMilliseconds() - perfStart;

        if (frame.width > 0) { // video frame
            //std.log.debug("decode video: {d} ms", .{perfDecode});

            perfStart = clock.now(io).toMilliseconds();
            const scaledFrame = try scaler.scale(frame);
            perfScale = clock.now(io).toMilliseconds() - perfStart;
            //std.log.debug("scale: {d} ms", .{perfScale});

            // calculate and await time to next frame render
            targetTimeNs = frame.pts * frameTimeNs;
            currentTimeNs = clock.now(io).toNanoseconds() - startTimeNs;
            if (currentTimeNs < targetTimeNs) {
                //std.log.info("sleep: {d}", .{targetTimeNs - targetTimeNs});
                const duration = std.Io.Duration.fromNanoseconds(targetTimeNs - currentTimeNs);
                try std.Io.sleep(io, duration, clock);
            } else {
                //std.log.err("lagg: {d}", .{currentTimeNs - targetTimeNs});
            }

            perfStart = clock.now(io).toMilliseconds();
            try frameRenderer.render(scaledFrame);
            perfRender = clock.now(io).toMilliseconds() - perfStart;
            //std.log.debug("render: {d} ms", .{perfRender});

            perfStart = clock.now(io).toMilliseconds();
        } else {
            //std.log.debug("decode audio: {d} ms", .{perfDecode});
            // TODO audio frame
        }
    } else |err| {
        if (err == error.EOF) {
            std.log.info("\nEOF reached", .{});
        }
    }

    mediaCtx.close();
}

fn getMode(args: []const [:0]const u8) renderer.RenderMode {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "-m")) {
            if (std.mem.eql(u8, args[i + 1], "0")) return renderer.RenderMode.ASCII;
            if (std.mem.eql(u8, args[i + 1], "1")) return renderer.RenderMode.GRAY;
        }
    }

    return renderer.RenderMode.ASCII;
}
