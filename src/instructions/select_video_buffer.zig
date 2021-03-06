const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const BufferID = @import("../values/buffer_id.zig");

/// Select the video buffer all subsequent DrawBackgroundPolygon, DrawSpritePolygon
/// and DrawString operations will draw into.
pub const Instance = struct {
    /// The buffer to select.
    buffer_id: BufferID.Enum,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) void {
        machine.selectVideoBuffer(self.buffer_id);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 2 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_id = try program.read(BufferID.Raw);

    return Instance{
        .buffer_id = try BufferID.parse(raw_id),
    };
}

pub const Error = Program.Error || BufferID.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.SelectVideoBuffer);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [2]u8{ raw_opcode, 0x00 };

    const invalid_buffer_id = [2]u8{ raw_opcode, 0x8B };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 2);

    try testing.expectEqual(.{ .specific = 0 }, instruction.buffer_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(parse, &BytecodeExamples.invalid_buffer_id, 2),
    );
}

test "execute calls selectVideoBuffer with correct parameters" {
    const instruction = Instance{
        .buffer_id = .back_buffer,
    };

    var machine = MockMachine.new(struct {
        pub fn selectVideoBuffer(buffer_id: BufferID.Enum) void {
            testing.expectEqual(.back_buffer, buffer_id) catch {
                unreachable;
            };
        }
    });

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.selectVideoBuffer);
}
