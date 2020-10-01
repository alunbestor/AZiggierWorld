const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");

const mem = @import("std").mem;
const introspection = @import("introspection.zig");

/// Returns a video buffer storage that packs 2 pixels into a single byte,
/// like the original Another World's buffers did.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const bytes_required = @divTrunc(width * height, 2) + @rem(width, 2);

    return struct {
        data: [bytes_required]u8 = [_]u8{0} ** bytes_required,

        const Self = @This();

        /// Return the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn get(self: Self, point: Point.Instance) ColorID.Trusted {
            const index = self.indexOf(point);
            const byte = self.data[index.offset];

            return @truncate(ColorID.Trusted, switch (index.hand) {
                .left => byte >> 4,
                .right => byte,
            });
        }

        /// Set the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn set(self: *Self, point: Point.Instance, color: ColorID.Trusted) void {
            const index = self.indexOf(point);
            const byte = &self.data[index.offset];

            byte.* = switch (index.hand) {
                .left => (byte.* & 0b0000_1111) | (@as(u8, color) << 4),
                .right => (byte.* & 0b1111_0000) | color,
            };
        }

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            const color_byte = (@as(u8, color) << 4) | color;
            mem.set(u8, &self.data, color_byte);
        }

        /// Given an X,Y point, returns the index of the byte within `data` containing that point's pixel,
        /// and whether the point is the left or right pixel in the byte.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        fn indexOf(self: Self, point: Point.Instance) Index {
            comptime const signed_width = @intCast(isize, width);
            const signed_address = @divFloor(point.x + (point.y * signed_width), 2);

            return .{
                .offset = @intCast(usize, signed_address),
                .hand = if (@rem(point.x, 2) == 0) .left else .right,
            };
        }
    };
}

/// The storage index for a pixel at a given point.
const Index = struct {
    /// The offset of the byte containing the pixel.
    offset: usize,
    /// Whether this pixel is the "left" (top 4 bits) or "right" (bottom 4 bits) of the byte.
    hand: enum(u1) {
        left,
        right,
    },
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Instance produces storage of the expected size filled with zeroes." {
    const storage = Instance(320, 200){};

    testing.expectEqual((320 * 200) / 2, storage.data.len);

    const expected_data = [_]u8{0} ** storage.data.len;

    testing.expectEqual(expected_data, storage.data);
}

test "indexOf returns expected offset and handedness" {
    const storage = Instance(320, 200){};

    testing.expectEqual(.{ .offset = 0, .hand = .left }, storage.indexOf(.{ .x = 0, .y = 0 }));
    testing.expectEqual(.{ .offset = 0, .hand = .right }, storage.indexOf(.{ .x = 1, .y = 0 }));
    testing.expectEqual(.{ .offset = 1, .hand = .left }, storage.indexOf(.{ .x = 2, .y = 0 }));
    testing.expectEqual(.{ .offset = 159, .hand = .right }, storage.indexOf(.{ .x = 319, .y = 0 }));
    testing.expectEqual(.{ .offset = 160, .hand = .left }, storage.indexOf(.{ .x = 0, .y = 1 }));

    testing.expectEqual(.{ .offset = 16_080, .hand = .left }, storage.indexOf(.{ .x = 160, .y = 100 }));
    testing.expectEqual(.{ .offset = 31_840, .hand = .left }, storage.indexOf(.{ .x = 0, .y = 199 }));
    testing.expectEqual(.{ .offset = 31_999, .hand = .right }, storage.indexOf(.{ .x = 319, .y = 199 }));

    // Uncomment to trigger runtime errors in test builds
    // _ = storage.address(.{ .x = 0, .y = 200 });
    // _ = storage.address(.{ .x = -1, .y = 0 });
}

test "get returns color at point" {
    var storage = Instance(320, 200){};
    storage.data[3] = 0b1010_0101;

    testing.expectEqual(0b0000, storage.get(.{ .x = 5, .y = 0 }));
    testing.expectEqual(0b1010, storage.get(.{ .x = 6, .y = 0 }));
    testing.expectEqual(0b0101, storage.get(.{ .x = 7, .y = 0 }));
}

test "set sets color at point" {
    var storage = Instance(320, 200){};

    storage.set(.{ .x = 6, .y = 0 }, 0b1010);
    storage.set(.{ .x = 7, .y = 0 }, 0b0101);

    testing.expectEqual(0b1010_0101, storage.data[3]);
}

test "fill replaces all bytes in buffer with specified color" {
    const fill_color: ColorID.Trusted = 0b0101;
    const color_byte: u8 = 0b0101_0101;

    var storage = Instance(320, 200){};

    const before_fill = [_]u8{0} ** storage.data.len;
    const after_fill = [_]u8{color_byte} ** storage.data.len;

    testing.expectEqual(before_fill, storage.data);

    storage.fill(fill_color);

    testing.expectEqual(after_fill, storage.data);
}