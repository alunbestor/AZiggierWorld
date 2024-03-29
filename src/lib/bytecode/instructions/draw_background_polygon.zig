const anotherworld = @import("../../anotherworld.zig");
const rendering = anotherworld.rendering;
const vm = anotherworld.vm;

const Point = rendering.Point;
const PolygonScale = rendering.PolygonScale;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;

/// Draw a polygon at the default zoom level and a constant position hardcoded in the bytecode.
/// Unlike DrawSpritePolygon this is likely intended for drawing backgrounds,
/// since the polygons cannot be scaled or repositioned programmatically.
pub const DrawBackgroundPolygon = struct {
    /// The address within the currently-loaded polygon resource from which to read polygon data.
    address: rendering.PolygonResource.Address,
    /// The X and Y position in screen space at which to draw the polygon.
    point: Point,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 4 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: Opcode.Raw, program: *Program) ParseError!Self {
        var self: Self = undefined;

        // Unlike all other instructions except DrawSpritePolygon, this instruction reuses bits from
        // the original opcode: the polygon address is constructed by combining the lowest 7 bits
        // of the opcode with the next 8 bits from the rest of the bytecode.
        // The combined value is then right-shifted to knock off the highest bit, which is always 1
        // (since that bit indicated this was a DrawBackgroundPolygon operation in the first place:
        // see opcode.zig).
        // Since the lowest bit will always be zero as a result, polygons must therefore start
        // on even address boundaries within Another World's polygon resources.
        const high_byte: rendering.PolygonResource.Address = raw_opcode;
        const low_byte: rendering.PolygonResource.Address = try program.read(u8);
        self.address = (high_byte << 8 | low_byte) << 1;

        // Copypasta from the original reference implementation:
        // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/8afc0f7d7d47f7700ad2e7d1cad33200ad29b17f/src/vm.cpp#L493-L496
        //
        // X,Y coordinates are consumed as a signed 16-bit integer but are encoded as a single unsigned byte each.
        // A single 0...255 byte isn't enough to cover the full 320-pixel width of the virtual screen,
        // so the remaining distance piggybacks off of the Y coordinate:
        // if the Y coordinate is at or beyond the 200-pixel virtual screen height,
        // substract the extra height to get the portion that belongs to the X coordinate.
        //
        // (TODO: figure out how points with a high X coordinate but a low Y coordinate were stored:
        // large vertex offsets within the polygon data instead?)
        self.point.x = try program.read(u8);
        self.point.y = try program.read(u8);
        const overflow = self.point.y - 199;
        if (overflow > 0) {
            self.point.y = 199;
            self.point.x += overflow;
        }

        return self;
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        try machine.drawPolygon(.polygons, self.address, self.point, .default);
    }

    // - Exported constants -

    pub const opcode = Opcode.DrawBackgroundPolygon;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        /// Example bytecode that should produce a valid instruction.
        pub const valid = low_x;

        const low_x = [4]u8{ 0b1000_1111, 0b0000_1111, 30, 40 };
        const high_x = [4]u8{ 0b1000_1111, 0b0000_1111, 255, 240 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses bytecode with low X coordinate and consumes 4 bytes" {
    const instruction = try expectParse(DrawBackgroundPolygon.parse, &DrawBackgroundPolygon.Fixtures.low_x, 4);

    // Address will be the first two bytes right-shifted by 1
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(30, instruction.point.x);
    try testing.expectEqual(40, instruction.point.y);
}

test "parse parses bytecode with high X coordinate and consumes 4 bytes" {
    const instruction = try expectParse(DrawBackgroundPolygon.parse, &DrawBackgroundPolygon.Fixtures.high_x, 4);

    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(255 + (240 - 199), instruction.point.x);
    try testing.expectEqual(199, instruction.point.y);
}

test "execute calls drawPolygon with correct parameters" {
    const instruction = DrawBackgroundPolygon{
        .address = 0xDEAD,
        .point = .{ .x = 320, .y = 200 },
    };

    var machine = mockMachine(struct {
        pub fn drawPolygon(source: vm.PolygonSource, address: rendering.PolygonResource.Address, point: Point, scale: PolygonScale) !void {
            try testing.expectEqual(.polygons, source);
            try testing.expectEqual(0xDEAD, address);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
            try testing.expectEqual(.default, scale);
        }
    });

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}
