//! Tests that parseNextInstruction all bytecode programs from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const Instruction = @import("../instructions/instruction.zig");
const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const ResourceDirectory = @import("../resources/resource_directory.zig");

const testing = @import("../utils/testing.zig");
const instrospection = @import("../utils/introspection.zig");
const validFixtureDir = @import("helpers.zig").validFixtureDir;
const std = @import("std");

/// Records and prints the details of a bytecode instruction that could not be parsed.
const ParseFailure = struct {
    resource_id: usize,
    offset: usize,
    parsed_bytes: [8]u8,
    parsed_count: usize,
    err: anyerror,

    fn init(resource_id: usize, program: *Program.Instance, offset: usize, err: anyerror) ParseFailure {
        const parsed_bytes = program.bytecode[offset..program.counter];

        var self = ParseFailure{
            .resource_id = resource_id,
            .offset = offset,
            .parsed_bytes = undefined,
            .parsed_count = parsed_bytes.len,
            .err = err,
        };
        std.mem.copy(u8, &self.parsed_bytes, parsed_bytes);
        return self;
    }

    fn opcodeName(self: ParseFailure) []const u8 {
        if (instrospection.intToEnum(Opcode.Enum, self.parsed_bytes[0])) |value| {
            return @tagName(value);
        } else |_| {
            return "Unknown";
        }
    }

    pub fn format(self: ParseFailure, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Resource #{} at {}\nOpcode: {s}\nBytes: {s}\nError: {s}", .{
            self.resource_id,
            self.offset,
            self.opcodeName(),
            std.fmt.fmtSliceHexUpper(self.parsed_bytes[0..self.parsed_count]),
            self.err,
        });
    }
};

test "parseNextInstruction parses all programs in fixture bytecode" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const repository = resource_directory.repository();

    var failures = std.ArrayList(ParseFailure).init(testing.allocator);
    defer failures.deinit();

    for (repository.resourceDescriptors()) |descriptor, index| {
        if (descriptor.type != .bytecode) continue;

        const data = try repository.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        var program = Program.new(data);

        while (program.isAtEnd() == false) {
            const last_valid_address = program.counter;
            if (Instruction.parseNextInstruction(&program)) {
                // Instruction parsing succeeded, hooray!
            } else |err| {
                // Log and continue parsing after encountering a failure
                try failures.append(ParseFailure.init(
                    index,
                    &program,
                    last_valid_address,
                    err,
                ));
            }
        }
    }

    if (failures.items.len > 0) {
        std.debug.print("\n{} instruction(s) failed to parse:\n", .{failures.items.len});
        for (failures.items) |failure| {
            std.debug.print("\n{s}\n\n", .{failure});
        }
    }

    try testing.expectEqual(0, failures.items.len);
}
