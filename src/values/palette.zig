const Color = @import("color.zig");
const static_limits = @import("../static_limits.zig");

/// The number of colors inside a palette.
const color_count = static_limits.color_count;

/// A 16-color palette of 24-bit colors.
pub const Instance = [color_count]Color.Instance;

pub const FixtureData = struct {
    // zig fmt: off

    /// A sample 16-color palette of 24-bit colors.
    pub const palette = Instance {
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
};
