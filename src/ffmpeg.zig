pub const ffmpeg = @cImport({
    @cInclude("libavutil/avutil.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
});
