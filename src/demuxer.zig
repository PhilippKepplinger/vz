const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const Demuxer = struct {
    avctx: ?*ffmpeg.AVFormatContext = null,
    currentPacket: *ffmpeg.AVPacket,

    pub fn init(file_path: [:0]const u8) !Demuxer {
        var avctx: ?*ffmpeg.AVFormatContext = null;
        const success: c_int = ffmpeg.avformat_open_input(&avctx, file_path, null, null);
        if (avctx != null and success == 0) {
            std.log.debug("AVFormatContext {s} opened", .{file_path});
            std.log.debug("Streams: {d}", .{avctx.?.nb_streams});
            return .{
                .avctx = avctx,
                .currentPacket = ffmpeg.av_packet_alloc(),
            };
        }

        return error.ErrorOpeningFile;
    }

    pub fn close(self: *@This()) void {
        ffmpeg.avformat_close_input(&self.avctx);
    }

    /// Reads the next encoded packet from the file
    pub fn readPacket(self: *@This()) !*ffmpeg.AVPacket {
        if (self.avctx == null) {
            return error.ErrorNoAVContext;
        }

        const result = ffmpeg.av_read_frame(self.avctx, self.currentPacket);
        if (result == ffmpeg.AVERROR_EOF) {
            return error.EOF;
        }
        if (result != 0) {
            std.log.err("read packet error: {d}", .{result});
        }

        return self.currentPacket;
    }
};
