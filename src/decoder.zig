const std = @import("std");
const Demuxer = @import("demuxer.zig").Demuxer;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const Decoder = struct {
    demuxer: Demuxer,
    video_ctx: ffmpeg.AVCodecContext = undefined,
    audio_ctx: ffmpeg.AVCodecContext = undefined,

    pub fn init(demuxer: Demuxer) !Decoder {
        return .{ .demuxer = demuxer };
    }

    fn initVideoCodecContext(self: @This()) !void {}

    fn initCodecContext(self: @This(), codecType: c_int) ![*c]ffmpeg.AVCodecContext {
        const avctx = self.demuxer.avctx.?;
        var codec_id: c_uint = 0;
        for (0..avctx.nb_streams) |i| {
            if (avctx.streams[i].*.codecpar.*.codec_type == ffmpeg.AVMEDIA_TYPE_VIDEO) {
                codec_id = avctx.streams[i].*.codecpar.*.codec_id;
                std.log.debug("codec_id: {d}", .{codec_id});
            }
        }

        if (codec_id == 0) {
            return error.ErrorNoVideoCodec;
        }

        const codec = ffmpeg.avcodec_find_decoder(codec_id);
        const codecCtx = ffmpeg.avcodec_alloc_context3(codec);

        const success: c_int = ffmpeg.avcodec_open2(codecCtx, avctx.video_codec, null);
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
};
