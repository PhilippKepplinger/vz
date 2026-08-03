const std = @import("std");
const Demuxer = @import("demuxer.zig").Demuxer;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const DecodingError = error{ PackageReadError, MissingFormatContext, CodecNotFound, DecoderNotFound, EndOfFile, DecodingError };

pub const Decoder = struct {
    demuxer: *Demuxer,
    video_ctx: *ffmpeg.AVCodecContext,
    audio_ctx: *ffmpeg.AVCodecContext,
    avframe: *ffmpeg.AVFrame,

    pub fn init(demuxer: *Demuxer) !Decoder {
        return .{ .demuxer = demuxer, .video_ctx = try initVideoCodecContext(demuxer), .audio_ctx = try initAudioCodecContext(demuxer), .avframe = ffmpeg.av_frame_alloc() };
    }

    fn initVideoCodecContext(demuxer: *Demuxer) DecodingError!*ffmpeg.AVCodecContext {
        return try initCodecContext(demuxer, ffmpeg.AVMEDIA_TYPE_VIDEO);
    }

    fn initAudioCodecContext(demuxer: *Demuxer) DecodingError!*ffmpeg.AVCodecContext {
        return try initCodecContext(demuxer, ffmpeg.AVMEDIA_TYPE_AUDIO);
    }

    fn initCodecContext(demuxer: *Demuxer, codecType: c_int) DecodingError![*c]ffmpeg.AVCodecContext {
        const avctx = demuxer.avctx.?;
        var codec_id: c_uint = 0;
        for (0..avctx.nb_streams) |i| {
            if (avctx.streams[i].*.codecpar.*.codec_type == codecType) {
                codec_id = avctx.streams[i].*.codecpar.*.codec_id;
                std.log.debug("codec_id: {d}", .{codec_id});
            }
        }

        if (codec_id == 0) {
            return DecodingError.CodecNotFound;
        }

        const codec = ffmpeg.avcodec_find_decoder(codec_id);
        const codecCtx = ffmpeg.avcodec_alloc_context3(codec);

        const success: c_int = ffmpeg.avcodec_open2(codecCtx, avctx.video_codec, null);
        if (success == 0) {
            std.log.debug("decoder initialized: {s}", .{codecCtx.*.codec.*.long_name});
            return codecCtx;
        }

        return DecodingError.DecoderNotFound;
    }

    pub fn decodeFrame(self: *@This()) DecodingError!*ffmpeg.AVFrame {
        // check if frame present
        var result = ffmpeg.avcodec_receive_frame(self.video_ctx, self.avframe);

        // EAGAIN means send another packet
        while (result == ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
            // send next packet into the decoder
            const packet = self.demuxer.readPacket() catch {
                return DecodingError.PackageReadError;
            };
            try self.decodePacket(packet);

            // check again if frame is present
            result = ffmpeg.avcodec_receive_frame(self.video_ctx, self.avframe);
        }

        if (result == 0) {
            std.log.debug("decoded frame: {d}x{d}", .{ self.avframe.width, self.avframe.height });
            return self.avframe;
        }

        if (result == ffmpeg.AVERROR_EOF) {
            std.log.debug("Reached EOF", .{});
            return DecodingError.EndOfFile;
        }

        std.log.err("Decoding error: {d}", .{result});
        return DecodingError.DecodingError; // TODO handle EOF
    }

    fn decodePacket(self: *@This(), pkt: *ffmpeg.AVPacket) DecodingError!void {
        const result = ffmpeg.avcodec_send_packet(self.video_ctx, pkt);

        if (result != 0) {
            std.log.err("Error decodePacket: {d}", .{result});
            return DecodingError.DecodingError;
        }
    }
};
