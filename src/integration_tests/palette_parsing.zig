//! Tests that look up polygon draw instructions and test that the corresponding
//! polygon addresses can be parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const PaletteResource = @import("../resources/palette_resource.zig");
const ResourceLoader = @import("../resources/resource_loader.zig");

const validFixturePath = @import("helpers.zig").validFixturePath;

const testing = @import("../utils/testing.zig");
const std = @import("std");
const fixedBufferStream = std.io.fixedBufferStream;
const countingReader = std.io.countingReader;

test "Parse all palettes in original game files" {
    const game_path = validFixturePath(testing.allocator) catch return;
    defer testing.allocator.free(game_path);

    const loader = try ResourceLoader.new(testing.allocator, game_path);
    defer loader.deinit();

    // For each resource, test that it can be parsed and decompressed without errors.
    for (loader.resource_descriptors) |descriptor| {
        if (descriptor.type != .palettes) continue;

        const data = try loader.readResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        var stream = countingReader(fixedBufferStream(data).reader());
        _ = try PaletteResource.parse(stream.reader());

        // Note: the original Another World DOS resources contained 32 palettes of 32 bytes each,
        // for 1024 bytes in total, but the resources were 2048 bytes large. It seems they store
        // the VGA palettes in the first 1024 bytes and the EGA palettes in the second.
        // We only use the first half of the palettes, and don't bother even reading the other half.
        // Reference: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/resource.h#L74
        try testing.expectEqual(PaletteResource.resource_size, stream.bytes_read);
    }
}
