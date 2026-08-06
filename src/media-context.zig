const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const MediaContext = struct {
    formatCtx: ?*ffmpeg.AVFormatContext = null,
    videoStream: *ffmpeg.AVStream,
    audioStream: *ffmpeg.AVStream, // TODO handle missing audio stream

    pub fn init(file_path: [:0]const u8) !MediaContext {
        var formatCtx: ?*ffmpeg.AVFormatContext = null;
        const success: c_int = ffmpeg.avformat_open_input(&formatCtx, file_path, null, null);

        if (formatCtx != null and success == 0) {
            std.log.debug("AVFormatContext {s} opened", .{file_path});
            std.log.debug("Streams: {d}", .{formatCtx.?.nb_streams});

            return .{
                .videoStream = try getVideoStream(formatCtx.?),
                .audioStream = try getAudioStream(formatCtx.?),
                .formatCtx = formatCtx,
            };
        }

        return error.ErrorOpeningFile;
    }

    fn getVideoStream(formatCtx: *ffmpeg.AVFormatContext) !*ffmpeg.AVStream {
        return try findStream(formatCtx, ffmpeg.AVMEDIA_TYPE_VIDEO);
    }

    fn getAudioStream(formatCtx: *ffmpeg.AVFormatContext) !*ffmpeg.AVStream {
        return try findStream(formatCtx, ffmpeg.AVMEDIA_TYPE_AUDIO);
    }

    fn findStream(formatCtx: *ffmpeg.AVFormatContext, codecType: c_int) !*ffmpeg.AVStream {
        for (0..formatCtx.nb_streams) |i| {
            if (formatCtx.streams[i].*.codecpar.*.codec_type == codecType) {
                return formatCtx.streams[i];
            }
        }

        return error.StreamNotFound;
    }

    pub fn close(self: *@This()) void {
        ffmpeg.avformat_close_input(&self.formatCtx);
    }
};
