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
            std.log.debug("Streams: {d}", .{avCtx.?.nb_streams});
            return .{ .avctx = avCtx };
        }

        return error.ErrorOpeningFile;
    }

    pub fn close(self: @This()) void {
        var tmp: ?*ffmpeg.AVFormatContext = self.avctx;
        ffmpeg.avformat_close_input(&tmp);
    }

    pub fn readPacket(self: *@This()) !*ffmpeg.AVPacket {
        if (self.avctx == null) {
            return error.ErrorNoAVContext;
        }

        const success = ffmpeg.av_read_frame(self.avctx, &self.avpkt);
        if (success == 0) {
            std.log.debug("packet read, size: {d}, stream: {d}", .{ self.avpkt.size, self.avpkt.stream_index });
            return &self.avpkt;
        }

        return error.ErrorReadPacket;
    }
};
