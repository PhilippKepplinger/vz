const std = @import("std");
const ffmpeg = @import("ffmpeg.zig").ffmpeg;
const demuxer = @import("demuxer.zig");
const decoder = @import("decoder.zig");

const BufferState = enum {
    FrameReady,
    EndOfFile,
};

pub const FrameReader = struct {
    demuxer: *demuxer.Demuxer,
    decoder: *decoder.Decoder,

    currentPacket: *ffmpeg.AVPacket,

    pub fn init(dmuxer: *demuxer.Demuxer, dcoder: *decoder.Decoder) !FrameReader {
        return .{
            .demuxer = dmuxer,
            .decoder = dcoder,
            .currentPacket = try dmuxer.readPacket(), // read first packet so its easier to decode
        };
    }

    pub fn next(self: *@This()) !*ffmpeg.AVFrame {
        try self.fillFrameBuffer();
        return try self.decoder.receiveFrame();
    }

    /// reads and decodes packets until a frame needs to be received, or EOF
    fn fillFrameBuffer(self: *@This()) !void {
        var packetConsumed = try self.decoder.decodePacket(self.currentPacket);

        while (packetConsumed) {
            self.currentPacket = try self.demuxer.readPacket();
            packetConsumed = try self.decoder.decodePacket(self.currentPacket);
        }
    }
};
