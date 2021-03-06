const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

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

    /// Allocates and returns a string containing the DOS filename for this file,
    /// as used by the MS-DOS version of Another World. The caller owns the returned slice.
    /// Returns an error if not enough memory could be allocated for the filename.
    pub fn dosName(self: Instance, allocator: *mem.Allocator) fmt.AllocPrintError![]const u8 {
        return switch (self) {
            .resource_list => fmt.allocPrint(allocator, "MEMLIST.BIN", .{}),
            .bank => |id| fmt.allocPrint(allocator, "BANK{X:0>2}", .{id}),
        };
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "dosName formats resource_list filename correctly" {
    const filename: Instance = .resource_list;

    const dos_name = try filename.dosName(testing.allocator);
    defer testing.allocator.free(dos_name);

    try testing.expectEqualStrings("MEMLIST.BIN", dos_name);
}

test "dosName formats single-digit bank filename with correct padding" {
    const filename: Instance = .{ .bank = 3 };

    const dos_name = try filename.dosName(testing.allocator);
    defer testing.allocator.free(dos_name);

    try testing.expectEqualStrings("BANK03", dos_name);
}

test "dosName formats two-decimal-digit bank filename as hex with correct padding" {
    const filename: Instance = .{ .bank = 10 };

    const dos_name = try filename.dosName(testing.allocator);
    defer testing.allocator.free(dos_name);

    try testing.expectEqualStrings("BANK0A", dos_name);
}

test "dosName formats two-hex-digit bank filename as two-digit hex" {
    const filename: Instance = .{ .bank = 0xFE };

    const dos_name = try filename.dosName(testing.allocator);
    defer testing.allocator.free(dos_name);

    try testing.expectEqualStrings("BANKFE", dos_name);
}

test "dosName returns error when memory could not be allocated" {
    const filename: Instance = .resource_list;

    try testing.expectError(
        error.OutOfMemory,
        filename.dosName(testing.failing_allocator),
    );
}
