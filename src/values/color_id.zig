//! Another World used 16-color palettes where each color is indexed by an integer from 0-15.
//! These color IDs appear in bytecode, polygon resources and video buffers.

const intCast = @import("../utils/introspection.zig").intCast;

/// A color index from 0-15. This is guaranteed to be valid.
pub const Trusted = u4;

/// A raw color index stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range: converted to a Trusted ID with `parse`.
pub const Raw = u8;

pub const Error = error{
    /// Bytecode specified an invalid color ID.
    InvalidColorID,
};

/// Given a raw byte value, return a trusted color ID.
/// Returns error.InvalidColorID if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    return intCast(Trusted, raw_id) catch error.InvalidColorID;
}

/// Remap colors 0...7 to colors 8...15. Colors 8...15 will be left as they are.
/// The last 8 colors in a palette are expected to be a lightened/darkened version of the first 8 colors;
/// Ramping them achieves translucency effects like e.g. the headlights of the ferrari in the game intro.
pub fn ramp(color: Trusted) Trusted {
    return color | 0b1000;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds for in-bounds integer" {
    testing.expectEqual(0, parse(0b0000_0000));
    testing.expectEqual(15, parse(0b0000_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    testing.expectError(error.InvalidColorID, parse(0b0001_0000));
}

test "ramp remaps lower 8 colors to upper 8 colors" {
    testing.expectEqual(0b1000, ramp(0b0000));
    testing.expectEqual(0b1001, ramp(0b0001));
    testing.expectEqual(0b1010, ramp(0b0010));
    testing.expectEqual(0b1011, ramp(0b0011));
    testing.expectEqual(0b1100, ramp(0b0100));
    testing.expectEqual(0b1101, ramp(0b0101));
    testing.expectEqual(0b1110, ramp(0b0110));
    testing.expectEqual(0b1111, ramp(0b0111));
}

test "ramp leaves upper 8 colors as they were" {
    testing.expectEqual(0b1000, ramp(0b1000));
    testing.expectEqual(0b1001, ramp(0b1001));
    testing.expectEqual(0b1010, ramp(0b1010));
    testing.expectEqual(0b1011, ramp(0b1011));
    testing.expectEqual(0b1100, ramp(0b1100));
    testing.expectEqual(0b1101, ramp(0b1101));
    testing.expectEqual(0b1110, ramp(0b1110));
    testing.expectEqual(0b1111, ramp(0b1111));
}
