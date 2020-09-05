const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

/// Wraps any bitwise reader in a reader that can read whole integers of arbitrary sizes.
pub fn new(bit_reader: anytype) Instance(@TypeOf(bit_reader)) {
    return Instance(@TypeOf(bit_reader)) { .bit_reader = bit_reader };
}

pub fn Instance(comptime Reader: type) type {
    const ReadBitError = @TypeOf(Reader.readBit).ReturnType.ErrorSet;
    const ValidationError = @TypeOf(Reader.validateAfterDecoding).ReturnType.ErrorSet;

    return struct {
        const Self = @This();

        bit_reader: Reader,

        /// Read a single bit from the underlying reader.
        pub fn readBit(self: *Self) ReadBitError!u1 {
            return self.bit_reader.readBit();
        }

        /// Returns a raw byte constructed by consuming 8 bits from the underlying reader.
        /// Returns an error if the required bits could not be read.
        pub fn readByte(self: *Self) ReadBitError!u8 {
            return self.readInt(u8);
        }
        
        /// Returns an unsigned integer constructed by consuming bits from the underlying reader
        /// up to the integer's width: e.g. readInt(u7) will consume 7 bits.
        /// Returns an error if the required bits could not be read.
        pub fn readInt(self: *Self, comptime Integer: type) ReadBitError!Integer {
            comptime assert(trait.isUnsignedInt(Integer));

            var value: Integer = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = Integer.bit_count;
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value = @shlExact(value, 1);
                value |= try self.bit_reader.readBit();
            }
            return value;
        }

        /// Whether the underlying reader has consumed all bits.
        pub fn isAtEnd(self: Self) bool {
            return self.bit_reader.isAtEnd();
        }

        /// Call once decoding is complete to verify that the underlying reader decoded all its data successfully.
        pub fn validateAfterDecoding(self: Self) ValidationError!void {
            return self.bit_reader.validateAfterDecoding();
        }
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const MockReader = @import("test_helpers/mock_reader.zig");

test "readInt reads integers of the specified width" {
    var parser = new(MockReader.new(u64, 0xDEAD_BEEF_0BAD_F00D));

    testing.expectEqual(0xDE, parser.readInt(u8));
    testing.expectEqual(0xAD, parser.readInt(u8));
    testing.expectEqual(0xBEEF, parser.readInt(u16));
    testing.expectEqual(0x0BADF00D, parser.readInt(u32));
    testing.expectEqual(true, parser.isAtEnd());
}

test "readInt returns error.SourceBufferEmpty when source buffer is too short" {
    var parser = new(MockReader.new(u8, 0xDE));

    testing.expectError(error.SourceBufferEmpty, parser.readInt(u16));
    testing.expectEqual(true, parser.isAtEnd());
}
