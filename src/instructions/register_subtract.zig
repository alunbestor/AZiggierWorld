const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig").Machine;
const RegisterID = @import("../values/register_id.zig");

pub const opcode = Opcode.Enum.RegisterSubtract;

/// Subtract the value in one register from another, wrapping on overflow.
pub const Instance = struct {
    /// The ID of the register to subtract from.
    destination: RegisterID.Enum,

    /// The ID of the register containing the value to subtract.
    source: RegisterID.Enum,

    pub fn execute(self: Instance, machine: *Machine) void {
        const source_value = machine.registers.signed(self.source);
        const destination_value = machine.registers.signed(self.destination);

        // Zig syntax: -% wraps on overflow, whereas - traps.
        const new_value = destination_value -% source_value;
        machine.registers.setSigned(self.destination, new_value);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    return Instance{
        .destination = RegisterID.parse(try program.read(RegisterID.Raw)),
        .source = RegisterID.parse(try program.read(RegisterID.Raw)),
    };
}

pub const ParseError = Program.ReadError;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 16, 17 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 3);

    try testing.expectEqual(RegisterID.parse(16), instruction.destination);
    try testing.expectEqual(RegisterID.parse(17), instruction.source);
}

test "execute subtracts from destination register and leaves source register alone" {
    const instruction = Instance{
        .destination = RegisterID.parse(16),
        .source = RegisterID.parse(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 125);
    machine.registers.setSigned(instruction.source, 50);

    instruction.execute(&machine);

    try testing.expectEqual(75, machine.registers.signed(instruction.destination));
    try testing.expectEqual(50, machine.registers.signed(instruction.source));
}

test "execute wraps on overflow" {
    const instruction = Instance{
        .destination = RegisterID.parse(16),
        .source = RegisterID.parse(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 32767);
    machine.registers.setSigned(instruction.source, -1);

    instruction.execute(&machine);

    try testing.expectEqual(-32768, machine.registers.signed(instruction.destination));
}

test "execute wraps on underflow" {
    const instruction = Instance{
        .destination = RegisterID.parse(16),
        .source = RegisterID.parse(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, -32768);
    machine.registers.setSigned(instruction.source, 1);

    instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers.signed(instruction.destination));
}
