const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;

pub const FrameScaler = struct {
    swsctx: ?*ffmpeg.SwsContext,
    scaledFrame: *ffmpeg.AVFrame,

    pub fn init(srcCodec: *ffmpeg.AVCodecContext, width: c_int, height: c_int, format: c_int) !FrameScaler {
        const srcAspect = getSrcAspect(srcCodec);
        const isScaleByHeight = scaleByHeight(srcCodec, width, height);

        const destWidth = if (isScaleByHeight) height * srcAspect else width;
        const destHeight = if (isScaleByHeight) height else width / srcAspect;

        std.log.debug("scaler format: {d}x{d}", .{ destWidth, destHeight });

        return .{
            .scaledFrame = ffmpeg.av_frame_alloc(),
            .swsctx = ffmpeg.sws_getContext(
                srcCodec.width,
                srcCodec.height,
                srcCodec.pix_fmt,
                @intFromFloat(destWidth),
                @intFromFloat(destHeight),
                format,
                ffmpeg.SWS_FAST_BILINEAR,
                null,
                null,
                null,
            ),
        };
    }

    fn scaleByHeight(codec: *ffmpeg.AVCodecContext, width: c_int, height: c_int) bool {
        const srcAspect = getSrcAspect(codec);
        const destAspect = toFloat(width) / toFloat(height);

        // destination is wider than source
        return destAspect > srcAspect;
    }

    fn getSrcAspect(codec: *ffmpeg.AVCodecContext) f64 {
        return toFloat(codec.width) / toFloat(codec.height);
    }

    fn toFloat(int: c_int) f64 {
        return @floatFromInt(int);
    }

    pub fn scale(self: *@This(), frame: *ffmpeg.AVFrame) !*ffmpeg.AVFrame {
        const result = ffmpeg.sws_scale_frame(self.swsctx, self.scaledFrame, frame);
        if (result < 0) {
            std.log.err("scaling error: {d}", .{result});
            return error.ScalingError;
        }

        return self.scaledFrame;
    }
};
