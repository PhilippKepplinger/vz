const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const demuxer = @import("demuxer.zig");
const decoder = @import("decoder.zig");

const BufferState = enum {
    FrameReady,
    EndOfFile,
};

pub const FrameReader = struct {
    io: std.Io,
    demuxer: *demuxer.Demuxer,
    decoder: *decoder.Decoder,

    currentPacket: *ffmpeg.AVPacket,
    frames: std.Io.Queue(*ffmpeg.AVFrame),
    buffer: []*ffmpeg.AVFrame = undefined,

    pub fn init(io: std.Io, buffer: []*ffmpeg.AVFrame, dmuxer: *demuxer.Demuxer, dcoder: *decoder.Decoder) !FrameReader {
        return .{
            .io = io,
            .demuxer = dmuxer,
            .decoder = dcoder,
            .buffer = buffer,
            .currentPacket = try dmuxer.readPacket(), // read first packet so its easier to decode
            .frames = .init(buffer),
        };
    }

    pub fn start(self: *@This()) !std.Thread {
        return try std.Thread.spawn(.{}, produceFrame, .{self});
    }

    /// gets the next decoded frame and puts it in the frame queue
    fn produceFrame(self: *@This()) !void {
        while (true) {
            try self.fillFrameBuffer();
            const frame = try self.decoder.receiveFrame();
            try self.frames.putOne(self.io, frame);
        }
    }

    /// reads and decodes packets until a frame needs to be received, or EOF
    fn fillFrameBuffer(self: *@This()) !void {
        while (try self.decoder.decodePacket(self.currentPacket)) {
            self.currentPacket = try self.demuxer.readPacket();
        }
    }

    /// feeds the decoder until a frame is ready and receives that frame
    pub fn next(self: *@This()) !*ffmpeg.AVFrame {
        return try self.frames.getOne(self.io);
    }
};
