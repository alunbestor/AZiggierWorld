const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const RegisterID = vm.RegisterID;

/// Copy the value of one register to another.
pub const RegisterCopy = struct {
    /// The ID of the register to copy into.
    destination: RegisterID,

    /// The ID of the register to copy from.
    source: RegisterID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        return Self{
            .destination = RegisterID.cast(try program.read(RegisterID.Raw)),
            .source = RegisterID.cast(try program.read(RegisterID.Raw)),
        };
    }

    pub fn execute(self: Self, machine: *Machine) void {
        const value = machine.registers.signed(self.source);
        machine.registers.setSigned(self.destination, value);
    }

    // - Exported constants -

    pub const opcode = Opcode.RegisterCopy;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [3]u8{ raw_opcode, 16, 17 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(RegisterCopy.parse, &RegisterCopy.Fixtures.valid, 3);

    try testing.expectEqual(RegisterID.cast(16), instruction.destination);
    try testing.expectEqual(RegisterID.cast(17), instruction.source);
}

test "execute updates specified register with value" {
    const instruction = RegisterCopy{
        .destination = RegisterID.cast(16),
        .source = RegisterID.cast(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 32767);
    machine.registers.setSigned(instruction.source, -900);

    instruction.execute(&machine);

    try testing.expectEqual(-900, machine.registers.signed(instruction.destination));
    try testing.expectEqual(-900, machine.registers.signed(instruction.source));
}
