const std = @import("std");
const Demuxer = @import("demuxer.zig").Demuxer;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const DecodingError = error{ PackageReadError, MissingFormatContext, CodecNotFound, DecoderNotFound, EndOfFile, DecodingError };

const StreamContext = struct {
    codec: *ffmpeg.AVCodecContext,
    stream_index: usize,
};

pub const Decoder = struct {
    demuxer: *Demuxer,
    videoInfo: StreamContext,
    audioInfo: StreamContext,
    avframe: *ffmpeg.AVFrame,
    lastUsedCodec: ?*ffmpeg.AVCodecContext = null,

    pub fn init(demuxer: *Demuxer) !Decoder {
        return .{
            .demuxer = demuxer,
            .videoInfo = try initVideoCodecContext(demuxer),
            .audioInfo = try initAudioCodecContext(demuxer),
            .avframe = ffmpeg.av_frame_alloc(),
        };
    }

    fn initVideoCodecContext(demuxer: *Demuxer) DecodingError!StreamContext {
        return try initCodecContext(demuxer, ffmpeg.AVMEDIA_TYPE_VIDEO);
    }

    fn initAudioCodecContext(demuxer: *Demuxer) DecodingError!StreamContext {
        return try initCodecContext(demuxer, ffmpeg.AVMEDIA_TYPE_AUDIO);
    }

    fn initCodecContext(demuxer: *Demuxer, codecType: c_int) DecodingError!StreamContext {
        const avctx = demuxer.avctx.?;
        var codec_id: c_uint = 0;
        var stream_index: usize = 0;
        var codecpars: ?*ffmpeg.AVCodecParameters = null;
        for (0..avctx.nb_streams) |i| {
            if (avctx.streams[i].*.codecpar.*.codec_type == codecType) {
                stream_index = i;
                codec_id = avctx.streams[i].*.codecpar.*.codec_id;
                codecpars = avctx.streams[i].*.codecpar;
                std.log.debug("codec_id: {d}, stream: {d}", .{ codec_id, i });
            }
        }

        const codec = ffmpeg.avcodec_find_decoder(codec_id);
        const codecCtx = ffmpeg.avcodec_alloc_context3(codec);
        if (codecpars) |pars| {
            const result = ffmpeg.avcodec_parameters_to_context(codecCtx, pars);
            if (result < 0) {
                return DecodingError.DecoderNotFound;
            }
        }

        const success = ffmpeg.avcodec_open2(codecCtx, codec, null);
        if (success == 0) {
            std.log.debug("decoder initialized: {s}", .{codecCtx.*.codec.*.long_name});
            return .{
                .codec = codecCtx,
                .stream_index = stream_index,
            };
        }

        return DecodingError.DecoderNotFound;
    }

    pub fn decodeFrame(self: *@This()) DecodingError!*ffmpeg.AVFrame {
        while (self.lastUsedCodec == null) {
            const packet = self.demuxer.readPacket() catch {
                return DecodingError.PackageReadError;
            };
            try self.decodePacket(packet);
        }

        // check if frame present
        // TODO decide for video and audio codecs
        var result = ffmpeg.avcodec_receive_frame(self.lastUsedCodec.?, self.avframe);

        // EAGAIN means send another packet
        while (result == ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
            // send next packet into the decoder
            const packet = self.demuxer.readPacket() catch {
                return DecodingError.PackageReadError;
            };
            try self.decodePacket(packet);

            // check again if frame is present
            result = ffmpeg.avcodec_receive_frame(self.lastUsedCodec.?, self.avframe);
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
        var codec: ?*ffmpeg.AVCodecContext = null;
        if (pkt.stream_index == self.videoInfo.stream_index) {
            codec = self.videoInfo.codec;
        } else if (pkt.stream_index == self.audioInfo.stream_index) {
            codec = self.audioInfo.codec;
        }

        if (codec == null) {
            return; // TODO what should happen? Skip packet for now..
        }

        self.lastUsedCodec = codec.?;
        const result = ffmpeg.avcodec_send_packet(codec, pkt);

        if (result != 0) {
            std.log.err("Error decodePacket: {d}", .{result});
            return DecodingError.DecodingError;
        }
    }
};
