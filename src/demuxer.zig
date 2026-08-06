const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const mctx = @import("media-context.zig");

pub const Demuxer = struct {
    mediaCtx: *mctx.MediaContext,
    currentPacket: *ffmpeg.AVPacket,

    pub fn init(mediaCtx: *mctx.MediaContext) !Demuxer {
        return .{
            .mediaCtx = mediaCtx,
            .currentPacket = ffmpeg.av_packet_alloc(),
        };
    }

    /// Reads the next encoded packet from the file
    pub fn readPacket(self: *@This()) !*ffmpeg.AVPacket {
        if (self.mediaCtx.formatCtx == null) {
            return error.ErrorNoAVContext;
        }

        const result = ffmpeg.av_read_frame(self.mediaCtx.formatCtx, self.currentPacket);
        if (result == ffmpeg.AVERROR_EOF) {
            return error.EOF;
        }
        if (result != 0) {
            std.log.err("read packet error: {d}", .{result});
        }

        return self.currentPacket;
    }
};
