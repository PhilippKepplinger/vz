const std = @import("std");
const Demuxer = @import("demuxer.zig").Demuxer;
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const DecodingError = error{
    DecoderNotFound,
    DecodingError,
    UnknownPacket,
    ReceiveFrameRequired,
    EndOfFile,
};

const StreamContext = struct {
    codec: *ffmpeg.AVCodecContext,
    stream_index: c_int,
};

pub const Decoder = struct {
    demuxer: *Demuxer,
    videoInfo: StreamContext,
    audioInfo: StreamContext,

    activeCodec: *ffmpeg.AVCodecContext = undefined,
    currentFrame: *ffmpeg.AVFrame,

    pub fn init(demuxer: *Demuxer) !Decoder {
        return .{
            .demuxer = demuxer,
            .videoInfo = try initVideoCodecContext(demuxer),
            .audioInfo = try initAudioCodecContext(demuxer),
            .currentFrame = ffmpeg.av_frame_alloc(),
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
        var stream_index: c_int = 0;
        var codecpars: ?*ffmpeg.AVCodecParameters = null;

        for (0..avctx.nb_streams) |i| {
            if (avctx.streams[i].*.codecpar.*.codec_type == codecType) {
                stream_index = avctx.streams[i].*.index;
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

    /// sends a packet to the decoder and returns the used codec context
    /// returns true if a frame is fully decoded, false => more packets required
    pub fn decodePacket(self: *@This(), pkt: *ffmpeg.AVPacket) DecodingError!bool {
        self.activeCodec = self.selectCodec(pkt.stream_index) catch {
            return true; // if the codec is unknown, needs more data => true
        };

        const result = ffmpeg.avcodec_send_packet(self.activeCodec, pkt);

        if (result == ffmpeg.AVERROR_EOF) {
            return DecodingError.EndOfFile;
        }
        if (result != 0 and result != ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
            std.log.err("Error decodePacket: {d}", .{result});
            return DecodingError.DecodingError;
        }

        return result == 0;
    }

    /// determines if the audio or video codec context is needed
    fn selectCodec(self: *@This(), streamIndex: c_int) !*ffmpeg.AVCodecContext {
        if (streamIndex == self.videoInfo.stream_index) {
            return self.videoInfo.codec;
        }
        if (streamIndex == self.audioInfo.stream_index) {
            return self.audioInfo.codec;
        }

        return error.UnsupportedStream;
    }

    /// receives a decoded frame
    /// EAGAIN => no frame readey, use decodePacket to feed the decoder
    /// EOF => no more frames available
    pub fn receiveFrame(self: *@This()) !*ffmpeg.AVFrame {
        const result = ffmpeg.avcodec_receive_frame(self.activeCodec, self.currentFrame);
        if (result == ffmpeg.AVERROR_EOF) {
            return error.EOF;
        }
        if (result == ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
            return error.EAGAIN;
        }

        return self.currentFrame;
    }
};
