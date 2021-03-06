const intCast = @import("../utils/introspection.zig").intCast;

/// The ID of a thread as a value from 0-63. This is guaranteed to be valid.
pub const Trusted = u6;

/// The raw ID of a thread as stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range.
pub const Raw = u8;

/// Thread ID 0 is treated as the main thread: program execution will begin on that thread.
pub const main: Trusted = 0;

pub const Error = error{
    /// Bytecode specified an invalid thread ID.
    InvalidThreadID,
};

/// Given a raw byte value, return a trusted thread ID.
/// Returns InvalidThreadID error if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    return intCast(Trusted, raw_id) catch error.InvalidThreadID;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds with in-bounds integer" {
    try testing.expectEqual(0x3F, parse(0x3F));
}

test "parse returns InvalidThreadID with out-of-bounds integer" {
    try testing.expectError(error.InvalidThreadID, parse(0x40));
}
