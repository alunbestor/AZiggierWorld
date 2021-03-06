const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Video = @import("../machine/video.zig");
const Point = @import("../values/point.zig");
const RegisterID = @import("../values/register_id.zig");
const PolygonScale = @import("../values/polygon_scale.zig");

/// Draw a polygon at a location and zoom level that are either hardcoded constants
/// or dynamic values read from registers.
pub const Instance = struct {
    /// The source location from which to read polygon data.
    source: Video.PolygonSource,

    /// The address within the polygon source from which to read polygon data.
    address: Video.PolygonAddress,

    /// The source for the X offset at which to draw the polygon.
    x: union(enum) {
        constant: Point.Coordinate,
        register: RegisterID.Raw,
    },

    /// The source for the Y offset at which to draw the polygon.
    y: union(enum) {
        constant: Point.Coordinate,
        register: RegisterID.Raw,
    },

    /// The source for the scale at which to draw the polygon.
    scale: union(enum) {
        default,
        constant: PolygonScale.Raw,
        register: RegisterID.Raw,
    },

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        const x = switch (self.x) {
            .constant => |constant| constant,
            .register => |id| machine.registers[id],
        };
        const y = switch (self.y) {
            .constant => |constant| constant,
            .register => |id| machine.registers[id],
        };
        const scale = switch (self.scale) {
            .constant => |constant| constant,
            .register => |id| @bitCast(PolygonScale.Raw, machine.registers[id]),
            .default => PolygonScale.default,
        };

        try machine.drawPolygon(self.source, self.address, .{ .x = x, .y = y }, scale);
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 5-8 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    var self: Instance = undefined;

    // Unlike DrawBackgroundPolygon, which treats the lower 7 bits of the opcode as the top part
    // of the polygon address, this operation reads the two bytes after the opcode as the polygon
    // address and uses the lower 6 bits of the opcode for other parts of the instruction (see below.)
    // It interprets the raw polygon address the same way as DrawBackgroundPolygon though,
    // right-shifting by one to land on an even address boundary.
    self.address = (try program.read(Video.PolygonAddress)) << 1;

    // The low 6 bits of the opcode byte determine where to read the x, y and scale values from,
    // and therefore how many bytes to consume for the operation.
    // This opcode byte has a layout of `01|xx|yy|ss`, where:
    //
    // - `01` was the initial opcode identifier that indicated this as a DrawSpritePolygon instruction
    // in the first place.
    //
    // - `xx` controls where to read the X offset from:
    //   - 00: read next 2 bytes as signed 16-bit constant
    //   - 01: read next byte as ID of register containing X coordinate
    //   - 10: read next byte as unsigned 8-bit constant
    //   - 11: read next byte as unsigned 8-bit constant, add 256
    //     (necessary since an 8-bit X coordinate can't address an entire 320-pixel-wide screen)
    //
    // - `yy` controls where to read the Y offset from:
    //   - 00: read next 2 bytes as signed 16-bit constant
    //   - 01: read next byte as ID of register containing Y coordinate
    //   - 10, 11: read next byte as unsigned 8-bit constant
    //
    // - `ss` controls where to read the scale from and which memory to read region polygon data from:
    //   - 00: use `.polygons` region, set default scale
    //   - 01: use `.polygons` region, read next byte as ID of register containing scale
    //   - 10: use `.polygons` region, read next byte as unsigned 8-bit constant
    //   - 11: use `.animations` region, set default scale

    const raw_x = @truncate(u2, raw_opcode >> 4);
    const raw_y = @truncate(u2, raw_opcode >> 2);
    const raw_scale = @truncate(u2, raw_opcode);

    self.x = switch (raw_x) {
        0b00 => .{ .constant = try program.read(Point.Coordinate) },
        0b01 => .{ .register = try program.read(RegisterID.Raw) },
        0b10 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
        0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) + 256 },
    };

    self.y = switch (raw_y) {
        0b00 => .{ .constant = try program.read(Point.Coordinate) },
        0b01 => .{ .register = try program.read(RegisterID.Raw) },
        0b10, 0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
    };

    switch (raw_scale) {
        0b00 => {
            self.source = .polygons;
            self.scale = .default;
        },
        0b01 => {
            self.source = .polygons;
            self.scale = .{ .register = try program.read(RegisterID.Raw) };
        },
        0b10 => {
            self.source = .polygons;
            self.scale = .{ .constant = @as(PolygonScale.Raw, try program.read(u8)) };
        },
        0b11 => {
            self.source = .animations;
            self.scale = .default;
        },
    }

    return self;
}

// -- Bytecode examples --

// zig fmt: off
pub const BytecodeExamples = struct {
    /// Example bytecode that should produce a valid instruction.
    pub const valid = wide_constants;

    const registers = [6]u8{
        0b01_01_01_01,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        1, 2, 3,                    // register IDs for x, y and scale
    };

    const wide_constants = [8]u8{
        0b01_00_00_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        0b1011_0110, 0b0010_1011,   // x constant (-18901 in two's-complement)
        0b0000_1101, 0b1000_1110,   // y constant (+3470 in two's-complement)
        255,                        // scale
    };

    const short_constants = [6]u8{
        0b01_10_10_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
        255,                        // scale
    };

    const short_boosted_x_constants = [6]u8{
        0b01_11_10_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        64, 200,                    // constants for x + 256 and y
        255,                        // scale
    };

    const default_scale_from_polygons = [5]u8{
        0b01_10_10_00,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
    };

    const default_scale_from_animations = [5]u8{
        0b01_10_10_11,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
    };
};
// zig fmt: on

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses all-registers instruction and consumes 6 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.registers, 6);

    try testing.expectEqual(.polygons, instruction.source);
    // Address is right-shifted by 1
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .register = 1 }, instruction.x);
    try testing.expectEqual(.{ .register = 2 }, instruction.y);
    try testing.expectEqual(.{ .register = 3 }, instruction.scale);
}

test "parse parses instruction with full-width constants and consumes 8 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.wide_constants, 8);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = -18901 }, instruction.x);
    try testing.expectEqual(.{ .constant = 3470 }, instruction.y);
    try testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with short constants and consumes 6 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.short_constants, 6);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with short constants with boosted X and consumes 6 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.short_boosted_x_constants, 6);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 64 + 256 }, instruction.x);
    try testing.expectEqual(.{ .constant = 200 }, instruction.y);
    try testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with default scale/polygon source and consumes 5 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.default_scale_from_polygons, 5);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.default, instruction.scale);
}

test "parse parses instruction with default scale/animation source and consumes 5 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.default_scale_from_animations, 5);

    try testing.expectEqual(.animations, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.default, instruction.scale);
}

test "execute with constants calls drawPolygon with correct parameters" {
    const instruction = Instance{
        .source = .animations,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .default,
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
            try testing.expectEqual(.animations, source);
            try testing.expectEqual(0xDEAD, address);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
            try testing.expectEqual(PolygonScale.default, scale);
        }
    });

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with registers calls drawPolygon with correct parameters" {
    const instruction = Instance{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .register = 1 },
        .y = .{ .register = 2 },
        .scale = .{ .register = 3 },
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
            try testing.expectEqual(.polygons, source);
            try testing.expectEqual(0xDEAD, address);
            try testing.expectEqual(-1234, point.x);
            try testing.expectEqual(5678, point.y);
            try testing.expectEqual(16384, scale);
        }
    });

    machine.registers[1] = -1234;
    machine.registers[2] = 5678;
    machine.registers[3] = 16384;

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with register scale value interprets value as unsigned" {
    const instruction = Instance{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .{ .register = 1 },
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(_source: Video.PolygonSource, _address: Video.PolygonAddress, _point: Point.Instance, scale: PolygonScale.Raw) !void {
            try testing.expectEqual(46635, scale);
        }
    });

    // 0b1011_0110_0010_1011 = -18901 in signed two's-complement;
    // Should be interpreted as 46635 when unsigned
    machine.registers[1] = -18901;

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}
