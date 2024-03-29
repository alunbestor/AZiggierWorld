//! Tests that Instruction.parse parses all bytecode programs from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const bytecode = anotherworld.bytecode;
const resources = anotherworld.resources;
const vm = anotherworld.vm;
const log = anotherworld.log;

const testing = @import("utils").testing;
const meta = @import("utils").meta;
const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const std = @import("std");

/// Records and prints the details of a bytecode instruction that could not be parsed.
const ParseFailure = struct {
    resource_id: usize,
    offset: usize,
    parsed_bytes: [8]u8,
    parsed_count: usize,
    err: anyerror,

    fn init(resource_id: usize, program: *bytecode.Program, offset: usize, err: anyerror) ParseFailure {
        const parsed_bytes = program.data[offset..program.counter];

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
        if (meta.intToEnum(bytecode.Opcode, self.parsed_bytes[0])) |value| {
            return @tagName(value);
        } else |_| {
            return "Unknown";
        }
    }

    pub fn format(self: ParseFailure, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Program resource #{} at offset {}\nOpcode: {s}\nParsed bytes: {s}\nError: {s}", .{
            self.resource_id,
            self.offset,
            self.opcodeName(),
            std.fmt.fmtSliceHexUpper(self.parsed_bytes[0..self.parsed_count]),
            self.err,
        });
    }
};

test "Instruction.parse parses all programs in fixture bytecode" {
    // Uncomment to print out statistics
    // testing.setLogLevel(.debug);

    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    var failures = std.ArrayList(ParseFailure).init(testing.allocator);
    defer failures.deinit();

    var min_frame_count: vm.FrameCount = std.math.maxInt(vm.FrameCount);
    var max_frame_count: vm.FrameCount = std.math.minInt(vm.FrameCount);

    for (reader.resourceDescriptors()) |descriptor, index| {
        if (descriptor.type != .bytecode) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        var program = try bytecode.Program.init(data);

        log.debug("Parsing program at resource #{}", .{index});

        while (program.isAtEnd() == false) {
            const last_valid_address = program.counter;
            if (bytecode.Instruction.parse(&program)) |any_instruction| {
                switch (any_instruction) {
                    .RegisterSet => |instruction| {
                        if (instruction.destination == .frame_duration) {
                            log.debug("RegisterSet frame duration: {}", .{instruction.value});
                            min_frame_count = @minimum(min_frame_count, @bitCast(vm.FrameCount, instruction.value));
                            max_frame_count = @maximum(max_frame_count, @bitCast(vm.FrameCount, instruction.value));
                        }
                    },
                    .RegisterAddConstant => |instruction| {
                        if (instruction.destination == .frame_duration) {
                            log.debug("RegisterAddConstant frame duration: {}", .{instruction.value});
                        }
                    },
                    else => {},
                }
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

    log.debug("Frame count min: {} max: {}", .{ min_frame_count, max_frame_count });

    if (failures.items.len > 0) {
        log.err("\n{} instruction(s) failed to parse:\n", .{failures.items.len});
        for (failures.items) |failure| {
            log.err("\n{s}\n\n", .{failure});
        }
    }

    try testing.expectEqual(0, failures.items.len);
}
