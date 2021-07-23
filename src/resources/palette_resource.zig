//! This file defines a parser that extracts 16-color palettes from Another World's palette resource data.
//! Each game part stored its own set of 32 palettes in a single resource that contained 32 runs of 16
//! 2-byte values: one 2-byte value for each color, one 32-byte run for each palette,
//! 1024 bytes for each palette resource.
//!
//! (However, in the MS-DOS version at least, the palette files were actually 2048 bytes long:
//! The game stored palettes for VGA graphics in the first half, and downgraded palettes for EGA graphics
//! in the second half. For now we only read and use the VGA palettes. Reference:
//! https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/resource.h#L74)
//!
//! Each color was 12 bits: 4 bits each for red, green and blue. These mapped to the 12-bit
//! color space of the original Amiga hardware that the game was developed on, documented here:
//! http://fabiensanglard.net/another_world_polygons_amiga500/index.html

const PaletteID = @import("../values/palette_id.zig");
const ColorID = @import("../values/color_id.zig");
const Color = @import("../values/color.zig");

const math = @import("std").math;

/// The number of palettes inside a palette resource.
pub const palette_count = 32;

/// The number of colors inside a palette.
pub const color_count = 16;

pub const Palette = [color_count]Color.Instance;

pub const Instance = [palette_count]Palette;

pub const palette_size = @sizeOf(Color.Raw) * color_count; // 32 bytes
pub const resource_size = palette_size * palette_count; // 1024 bytes

/// Parse an Another World palette resource into 32 16-color RGB palettes.
pub fn parse(reader: anytype) !Instance {
    var self: Instance = undefined;

    var offset: usize = 0;
    for (self) |*palette| {
        for (palette.*) |*color| {
            color.* = Color.parse(try reader.readInt(Color.Raw, .Big));
        }
    }

    return self;
}

// -- Examples --

const DataExamples = struct {
    // zig fmt: off
    const palette = [palette_size]u8 {
        0x00, 0x00, // color 0
        0x01, 0x11, // color 1
        0x02, 0x22, // color 2
        0x03, 0x33, // color 3
        0x04, 0x44, // color 4
        0x05, 0x55, // color 5
        0x06, 0x66, // color 6
        0x07, 0x77, // color 7
        0x08, 0x88, // color 8
        0x09, 0x99, // color 9
        0x0A, 0xAA, // color 10
        0x0B, 0xBB, // color 11
        0x0C, 0xCC, // color 12
        0x0D, 0xDD, // color 13
        0x0E, 0xEE, // color 14
        0x0F, 0xFF, // color 15
    };

    const resource: [resource_size]u8 = palette ** palette_count;
    // zig fmt: on
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;
const countingReader = @import("std").io.countingReader;

test "parse parses expected palettes from resource" {
    // zig fmt: off
    const expected_palette = Palette {
        .{ .r = 0,      .g = 0,     .b = 0 },    // color 0
        .{ .r = 16,     .g = 16,    .b = 16 },   // color 1
        .{ .r = 32,     .g = 32,    .b = 32 },   // color 2
        .{ .r = 48,     .g = 48,    .b = 48 },   // color 3
        .{ .r = 68,     .g = 68,    .b = 68 },   // color 4
        .{ .r = 84,     .g = 84,    .b = 84 },   // color 5
        .{ .r = 100,    .g = 100,   .b = 100 },  // color 6
        .{ .r = 116,    .g = 116,   .b = 116 },  // color 7
        .{ .r = 136,    .g = 136,   .b = 136 },  // color 8
        .{ .r = 152,    .g = 152,   .b = 152 },  // color 9
        .{ .r = 168,    .g = 168,   .b = 168 },  // color 10
        .{ .r = 184,    .g = 184,   .b = 184 },  // color 11
        .{ .r = 204,    .g = 204,   .b = 204 },  // color 12
        .{ .r = 220,    .g = 220,   .b = 220 },  // color 13
        .{ .r = 236,    .g = 236,   .b = 236 },  // color 14
        .{ .r = 252,    .g = 252,   .b = 252 },  // color 15
    };
    // zig fmt: on

    const data = &DataExamples.resource;
    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try parse(stream.reader());

    for (actual) |palette| {
        try testing.expectEqualSlices(Color.Instance, &expected_palette, &palette);
    }

    try testing.expectEqual(1024, stream.bytes_read);
}

test "parse returns error.EndOfStream on truncated data" {
    const data = DataExamples.resource[0..1023];
    var stream = countingReader(fixedBufferStream(data).reader());
    try testing.expectError(error.EndOfStream, parse(stream.reader()));
    try testing.expectEqual(1023, stream.bytes_read);
}
