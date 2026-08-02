const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const Demuxer = struct {
    avctx: ?*ffmpeg.AVFormatContext = null,
    avpkt: ffmpeg.AVPacket = undefined,

    pub fn init(file_path: [:0]const u8) !Demuxer {
        var avCtx: ?*ffmpeg.AVFormatContext = null;
        const success: c_int = ffmpeg.avformat_open_input(&avCtx, file_path, null, null);
        if (success == 0) {
            std.log.debug("AVFormatContext {s} opened", .{file_path});
            return .{ .avctx = avCtx };
        }

        return error.ErrorOpeningFile;
    }

    pub fn close(self: @This()) void {
        var tmp: ?*ffmpeg.AVFormatContext = self.avctx;
        ffmpeg.avformat_close_input(&tmp);
    }

    pub fn readPacket(self: @This()) !*ffmpeg.AVPacket {
        if (self.avctx == null) {
            return error.ErrorNoAVContext;
        }

        const success: c_int = ffmpeg.av_read_frame(self.avctx, &self.avPacket);
        if (success == 0) {
            std.log.debug("packet read, size: {d}", .{self.avPacket.size});
            return &self.avPacket;
        }

        return error.ErrorReadPacket;
    }
};

pub fn initVideoDecoder(ctx: *ffmpeg.AVFormatContext) ![*c]ffmpeg.AVCodecContext {
    var codec_id: c_uint = 0;
    for (0..ctx.nb_streams) |i| {
        if (ctx.streams[i].*.codecpar.*.codec_type == ffmpeg.AVMEDIA_TYPE_VIDEO) {
            codec_id = ctx.streams[i].*.codecpar.*.codec_id;
            std.log.debug("codec_id: {d}", .{codec_id});
        }
    }

    if (codec_id == 0) {
        return error.ErrorNoVideoCodec;
    }

    const codec = ffmpeg.avcodec_find_decoder(codec_id);
    const codecCtx = ffmpeg.avcodec_alloc_context3(codec);

    const success: c_int = ffmpeg.avcodec_open2(codecCtx, ctx.video_codec, null);
    if (success == 0) {
        std.log.debug("decoder initialized: {s}", .{codecCtx.*.codec.*.long_name});
        return codecCtx;
    }

    return error.ErrorInitDecoder;
}

pub fn decodePacket(avctx: *ffmpeg.AVCodecContext, pkt: *ffmpeg.AVPacket) !void {
    const result = ffmpeg.avcodec_send_packet(avctx, pkt);
    if (result != 0) {
        return error.ErrorDecodePacket;
    }
}

pub fn receiveFrame(avctx: *ffmpeg.AVCodecContext, frame: *ffmpeg.AVFrame) !void {
    const result = ffmpeg.avcodec_receive_frame(avctx, frame);

    if (result == ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
        return error.NoFrame;
    } else if (result != 0) {
        return error.ErrorReceiveFrame;
    }
}
