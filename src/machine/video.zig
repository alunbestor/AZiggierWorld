//! Extends Machine.Instance with methods for rendering to the virtual screen.

const Machine = @import("machine.zig");
const Point = @import("../values/point.zig");
const ColorID = @import("../values/color_id.zig");
const StringID = @import("../values/string_id.zig");
const BufferID = @import("../values/buffer_id.zig");

const english = @import("../assets/english.zig");

/// Defines where to read polygon from for a polygon draw operation.
/// Another World's polygons may be stored in one of two locations:
/// - polygons: A game-part-specific resource containing scene backgrounds and incidental animations.
/// - animations: A shared resource containing common sprites like players, enemies, weapons etc.
pub const PolygonSource = enum {
    /// Draw polygon data from the currently-loaded polygon resource.
    polygons,
    /// Draw polygon data from the currently-loaded animation resource.
    animations,
};

/// The offset within a polygon or animation resource from which to read polygon data.
pub const PolygonAddress = u16;

/// The scale at which to render a polygon.
/// This is a raw value that will be divided by 64 to determine the actual scale:
/// e.g. 64 is 1x, 32 is 0.5x, 96 is 1.5x, 256 is 4x etc.
pub const PolygonScale = u16;

/// The default scale for polygon draw operations.
/// This renders polygons at their native size.
pub const default_scale: PolygonScale = 64;

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

/// Methods intended to be imported into Machine.Instance.
pub const Interface = struct {
    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// If scale is `null`, the polygon will be drawn at its default scale.
    /// Returns an error if the specified polygon address was invalid.
    pub fn drawPolygon(self: *Machine.Instance, source: PolygonSource, address: PolygonAddress, point: Point.Instance, scale: PolygonScale) !void {
        log_unimplemented("Video.drawPolygon: draw {}.{X} at x:{} y:{} scale:{}", .{
            @tagName(source),
            address,
            point.x,
            point.y,
            scale,
        });
    }

    /// Render a string from the current string table at the specified screen position in the specified color.
    /// Returns an error if the string could not be found.
    pub fn drawString(self: *Machine.Instance, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        log_unimplemented("Video.drawString: draw #{} color:{} at x:{} y:{}", .{
            try english.find(string_id),
            color_id,
            point.x,
            point.y,
        });
    }

    pub fn selectVideoBuffer(self: *Machine.Instance, buffer_id: BufferID.Enum) void {
        log_unimplemented("Video.selectVideoBuffer: {}", .{buffer_id});
    }
};
