const std = @import("std");
const mctx = @import("media-context.zig");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const DecodingError = error{
    DecoderNotFound,
    DecodingError,
    UnknownPacket,
    ReceiveFrameRequired,
    EndOfFile,
};

pub const Decoder = struct {
    mediaCtx: *mctx.MediaContext,
    videoCodec: *ffmpeg.AVCodecContext,
    audioCodec: *ffmpeg.AVCodecContext,

    activeCodec: *ffmpeg.AVCodecContext = undefined,

    pub fn init(mediaCtx: *mctx.MediaContext) !Decoder {
        return .{
            .mediaCtx = mediaCtx,
            .videoCodec = try initVideoCodecContext(mediaCtx),
            .audioCodec = try initAudioCodecContext(mediaCtx),
        };
    }

    fn initVideoCodecContext(mediaCtx: *mctx.MediaContext) DecodingError!*ffmpeg.AVCodecContext {
        return try initCodecContext(mediaCtx.videoStream);
    }

    fn initAudioCodecContext(mediaCtx: *mctx.MediaContext) DecodingError!*ffmpeg.AVCodecContext {
        return try initCodecContext(mediaCtx.audioStream);
    }

    fn initCodecContext(stream: *ffmpeg.AVStream) DecodingError!*ffmpeg.AVCodecContext {
        const codec = ffmpeg.avcodec_find_decoder(stream.codecpar.*.codec_id);
        const codecCtx = ffmpeg.avcodec_alloc_context3(codec);
        if (stream.codecpar) |pars| {
            const result = ffmpeg.avcodec_parameters_to_context(codecCtx, pars);
            if (result < 0) {
                return DecodingError.DecoderNotFound;
            }
        }

        const success = ffmpeg.avcodec_open2(codecCtx, codec, null);
        if (success == 0) {
            std.log.debug("decoder initialized: {s}", .{codecCtx.*.codec.*.long_name});
            return codecCtx;
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
        if (streamIndex == self.mediaCtx.videoStream.index) {
            return self.videoCodec;
        }
        if (streamIndex == self.mediaCtx.audioStream.index) {
            return self.audioCodec;
        }

        return error.UnsupportedStream;
    }

    /// receives a decoded frame
    /// EAGAIN => no frame readey, use decodePacket to feed the decoder
    /// EOF => no more frames available
    pub fn receiveFrame(self: *@This()) !*ffmpeg.AVFrame {
        const frame = ffmpeg.av_frame_alloc();
        const result = ffmpeg.avcodec_receive_frame(self.activeCodec, frame);
        if (result == ffmpeg.AVERROR_EOF) {
            return error.EOF;
        }
        if (result == ffmpeg.AVERROR(ffmpeg.EAGAIN)) {
            return error.EAGAIN;
        }

        return frame;
    }
};
