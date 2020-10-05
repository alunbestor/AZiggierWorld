const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");
const Range = @import("../../values/range.zig");
const PolygonDrawMode = @import("../../values/polygon_draw_mode.zig");

const mem = @import("std").mem;

/// Returns a video buffer storage that stores a single pixel per byte.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const Data = [height][width]ColorID.Trusted;

    return struct {
        const Self = @This();

        data: Data = mem.zeroes(Data),

        // -- Type-level functions --

        /// A no-op: AlignedStorage stores 4-bit values natively.
        /// Used in APIs that need to talk to an AlignedStorage or a PackedStorage.
        pub fn nativeColor(color: ColorID.Trusted) NativeColor {
            return color;
        }

        // -- Public instance methods --

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            // It would be nice to use mem.set on self.data as a whole,
            // but that doesn't work on multidimensional arrays.
            for (self.data) |*row| {
                mem.set(NativeColor, row, color);
            }
        }

        /// Draws a single pixel at the specified point, deriving its color from the specified draw mode.
        /// Used for drawing single-pixel polygons.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedDrawPixel(self: *Self, point: Point.Instance, draw_mode: PolygonDrawMode.Enum, mask_source: *const Self) void {
            const color = switch (draw_mode) {
                .solid_color => |color_id| color_id,
                .highlight => ColorID.highlight(self.uncheckedGet(point)),
                .mask => mask_source.uncheckedGet(point),
            };

            self.uncheckedSetNativeColor(point, color);
        }

        /// Sets a single pixel at the specified point to the specified color.
        /// Used for drawing solid font glyphs, which don't need the extra complexity of uncheckedDrawPixel.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedSetNativeColor(self: *Self, point: Point.Instance, color: NativeColor) void {
            self.data[@intCast(usize, point.y)][@intCast(usize, point.x)] = color;
        }

        /// Fill a horizontal line with colors using the specified draw mode.
        /// This is not bounds-checked: specifying a span outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        pub fn uncheckedDrawSpan(self: *Self, x_span: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: PolygonDrawMode.Enum, mask_source: *const Self) void {
            const row = @intCast(usize, y);
            const start_column = @intCast(usize, x_span.min);
            // Ranges are inclusive, but this range will be converted into a slice,
            // and Zig's [start..end] slice syntax does not include the end offset.
            const end_column = @intCast(usize, x_span.max) + 1;

            var destination_slice = self.data[row][start_column..end_column];

            switch (draw_mode) {
                .solid_color => |color_id| {
                    mem.set(NativeColor, destination_slice, color_id);
                },
                .highlight => {
                    for (destination_slice) |*pixel| {
                        pixel.* = ColorID.highlight(pixel.*);
                    }
                },
                .mask => {
                    const mask_slice = mask_source.data[row][start_column..end_column];
                    mem.copy(NativeColor, destination_slice, mask_slice);
                },
            }
        }

        // -- Private instance methods --

        // Returns the color of the pixel at the specified point.
        fn uncheckedGet(self: Self, point: Point.Instance) NativeColor {
            return self.data[@intCast(usize, point.y)][@intCast(usize, point.x)];
        }
    };
}

// The unit in which the buffer will read and write pixel color values.
const NativeColor = ColorID.Trusted;

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Instance produces storage of the expected size filled with zeroes." {
    const storage = Instance(320, 200){};

    const ExpectedData = [200][320]ColorID.Trusted;

    testing.expectEqual(ExpectedData, @TypeOf(storage.data));

    const expected_data = mem.zeroes(ExpectedData);

    testing.expectEqual(expected_data, storage.data);
}

test "Instance handles 0 width or height gracefully" {
    const zero_height = Instance(320, 0){};
    testing.expectEqual([0][320]ColorID.Trusted, @TypeOf(zero_height.data));

    const zero_width = Instance(0, 200){};
    testing.expectEqual([200][0]ColorID.Trusted, @TypeOf(zero_width.data));

    const zero_dimensions = Instance(0, 0){};
    testing.expectEqual([0][0]ColorID.Trusted, @TypeOf(zero_dimensions.data));
}

test "fillWithNativeColor replaces all bytes in buffer with specified color" {
    var storage = Instance(4, 4){};

    const before_fill = @TypeOf(storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    const after_fill = @TypeOf(storage.data){
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
    };

    testing.expectEqual(before_fill, storage.data);

    storage.fill(15);

    testing.expectEqual(after_fill, storage.data);
}

test "uncheckedSetNativeColor sets color at point" {
    var storage = Instance(320, 200){};

    storage.uncheckedSetNativeColor(.{ .x = 0, .y = 0 }, 15);
    storage.uncheckedSetNativeColor(.{ .x = 3, .y = 4 }, 10);
    storage.uncheckedSetNativeColor(.{ .x = 319, .y = 199 }, 1);

    testing.expectEqual(15, storage.data[0][0]);
    testing.expectEqual(10, storage.data[4][3]);
    testing.expectEqual(1, storage.data[199][319]);
}
