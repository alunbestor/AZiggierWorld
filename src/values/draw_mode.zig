const ColorID = @import("../values/color_id.zig");

/// The modes in which a polygon can be drawn.
pub const DrawMode = union(enum) {
    /// Render the polygon in a solid opaque color using the specified color index.
    solid_color: ColorID.Trusted,

    /// Remap the colors within the area of the polygon into their "highlighted" versions.
    /// This is used for translucency and lighting effects, like the ferrari headlights
    /// and particle accelerator flashes in the intro.
    /// See https://fabiensanglard.net/another_world_polygons/index.html for visual examples.
    highlight,

    /// Treat the polygon as a mask: fill it with pixels read from the corresponding
    /// location in another video buffer.
    /// This is likely used for foreground objects that occlude the player and enemies,
    /// but that were drawn into a background buffer.
    mask,

    const Self = @This();

    /// A raw draw mode, stored in bytecode as an 8-bit unsigned integer.
    pub const Raw = u8;

    pub fn parse(raw: Raw) Self {
        return switch (raw) {
            0...15 => |color_id| .{ .solid_color = @intCast(ColorID.Trusted, color_id) },
            16 => .highlight,
            // TODO: check if there's a specific constant the game always uses for mask.
            else => .mask,
        };
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse correctly parses raw draw mode" {
    try testing.expectEqual(.{ .solid_color = 1 }, DrawMode.parse(1));
    try testing.expectEqual(.{ .solid_color = 0 }, DrawMode.parse(0));
    try testing.expectEqual(.{ .solid_color = 2 }, DrawMode.parse(2));
    try testing.expectEqual(.{ .solid_color = 3 }, DrawMode.parse(3));
    try testing.expectEqual(.{ .solid_color = 4 }, DrawMode.parse(4));
    try testing.expectEqual(.{ .solid_color = 5 }, DrawMode.parse(5));
    try testing.expectEqual(.{ .solid_color = 6 }, DrawMode.parse(6));
    try testing.expectEqual(.{ .solid_color = 7 }, DrawMode.parse(7));
    try testing.expectEqual(.{ .solid_color = 8 }, DrawMode.parse(8));
    try testing.expectEqual(.{ .solid_color = 9 }, DrawMode.parse(9));
    try testing.expectEqual(.{ .solid_color = 10 }, DrawMode.parse(10));
    try testing.expectEqual(.{ .solid_color = 11 }, DrawMode.parse(11));
    try testing.expectEqual(.{ .solid_color = 12 }, DrawMode.parse(12));
    try testing.expectEqual(.{ .solid_color = 13 }, DrawMode.parse(13));
    try testing.expectEqual(.{ .solid_color = 14 }, DrawMode.parse(14));
    try testing.expectEqual(.{ .solid_color = 15 }, DrawMode.parse(15));

    try testing.expectEqual(.highlight, DrawMode.parse(16));
    try testing.expectEqual(.mask, DrawMode.parse(17));
    try testing.expectEqual(.mask, DrawMode.parse(255));
}
