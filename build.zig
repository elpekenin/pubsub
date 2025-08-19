const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("pubsub", .{
        .root_source_file = b.path("src/pubsub.zig"),
    });
}
