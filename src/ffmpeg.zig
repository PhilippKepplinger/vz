const std = @import("std");
const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
});

pub fn open(io: std.Io, file_path: [:0]const u8) !*c.AVFormatContext {
    _ = io;
    var avCtx: ?*c.AVFormatContext = null;
    const success: c_int = c.avformat_open_input(&avCtx, file_path, null, null);
    if (success == 0) {
        std.log.debug("file {s} opened", .{file_path});
        return avCtx.?;
    }

    return error.ErrorOpeningFile;
}

pub fn readPacket(ctx: *c.AVFormatContext) !c.AVPacket {
    var avPacket: c.AVPacket = undefined;
    const success: c_int = c.av_read_frame(ctx, &avPacket);
    if (success == 0) {
        std.log.debug("packet read, size: {d}", .{avPacket.size});
        return avPacket;
    }

    return error.ErrorReadPacket;
}

pub fn initVideoDecoder(ctx: *c.AVFormatContext) ![*c]c.AVCodecContext {
    var codec_id: c_uint = 0;
    for (0..ctx.nb_streams) |i| {
        if (ctx.streams[i].*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
            codec_id = ctx.streams[i].*.codecpar.*.codec_id;
            std.log.debug("codec_id: {d}", .{codec_id});
        }
    }

    if (codec_id == 0) {
        return error.ErrorNoVideoCodec;
    }

    const codec = c.avcodec_find_decoder(codec_id);
    const codecCtx = c.avcodec_alloc_context3(codec);

    const success: c_int = c.avcodec_open2(codecCtx, ctx.video_codec, null);
    if (success == 0) {
        std.log.debug("decoder initialized: {s}", .{codecCtx.*.codec.*.long_name});
        return codecCtx;
    }

    return error.ErrorInitDecoder;
}

pub fn decodePacket(avctx: *c.AVCodecContext, pkt: *c.AVPacket) !void {
    const result = c.avcodec_send_packet(avctx, pkt);
    if (result != 0) {
        return error.ErrorDecodePacket;
    }
}
