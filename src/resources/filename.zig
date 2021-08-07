const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

/// DOS 8.3 filenames require a maximum of 12 characters to represent.
const max_filename_length = 12;

/// A buffer large enough to hold a filename.
pub const Buffer = [max_filename_length]u8;

/// The type of a bank filename identifier.
/// These are in the range 01-0D for the MS-DOS version of Another World.
pub const BankID = u8;

/// Describes all legal filenames for Another World resource files.
pub const Instance = union(enum) {
    /// A manifest of where each resource is located within the bank files.
    /// Named `MEMLIST.BIN` in the MS-DOS version.
    resource_list,

    /// An archive containing one or more compressed game resources.
    /// Named `BANK01`–`BANK0D` in the MS-DOS version.
    bank: BankID,

    /// Given a buffer of suitable size, populates the buffer with the DOS filename
    /// for this file. Returns the slice of `buffer` that contains the entire filename.
    pub fn dosName(self: Instance, buffer: *Buffer) []const u8 {
        return switch (self) {
            // Use catch unreachable because we know at compile time that the Buffer type
            // will be large enough to contain the formatted name.
            .resource_list => fmt.bufPrint(buffer, "MEMLIST.BIN", .{}) catch unreachable,
            .bank => |id| fmt.bufPrint(buffer, "BANK{X:0>2}", .{id}) catch unreachable,
        };
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "dosName formats resource_list filename correctly" {
    const filename: Instance = .resource_list;

    var buffer: Buffer = undefined;
    const dos_name = filename.dosName(&buffer);

    try testing.expectEqualStrings("MEMLIST.BIN", dos_name);
}

test "dosName formats single-digit bank filename with correct padding" {
    const filename: Instance = .{ .bank = 3 };

    var buffer: Buffer = undefined;
    const dos_name = filename.dosName(&buffer);

    try testing.expectEqualStrings("BANK03", dos_name);
}

test "dosName formats two-decimal-digit bank filename as hex with correct padding" {
    const filename: Instance = .{ .bank = 10 };

    var buffer: Buffer = undefined;
    const dos_name = filename.dosName(&buffer);

    try testing.expectEqualStrings("BANK0A", dos_name);
}

test "dosName formats two-hex-digit bank filename as two-digit hex" {
    const filename: Instance = .{ .bank = 0xFE };

    var buffer: Buffer = undefined;
    const dos_name = filename.dosName(&buffer);

    try testing.expectEqualStrings("BANKFE", dos_name);
}
