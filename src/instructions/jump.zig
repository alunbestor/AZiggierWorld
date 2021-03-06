const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Address = @import("../values/address.zig");

pub const Error = Program.Error;

/// Unconditionally jump to a new address.
/// Unlike Call, this does not increment the stack with a return address.
pub const Instance = struct {
    /// The address to jump to.
    address: Address.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        try machine.program.jump(self.address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .address = try program.read(Address.Raw),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.Jump);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 3);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "execute jumps to new address and does not affect stack depth" {
    const instruction = Instance{
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.new();
    machine.program = Program.new(&bytecode);

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute returns error.InvalidAddress when address is out of range" {
    const instruction = Instance{
        .address = 1000,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.new();
    machine.program = Program.new(&bytecode);
    try testing.expectError(error.InvalidAddress, instruction.execute(&machine));
}
