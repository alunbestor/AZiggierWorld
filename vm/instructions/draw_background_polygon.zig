const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const Video = @import("../video.zig");
const Point = @import("../types/point.zig");

/// Draw a polygon at the default zoom level and a constant position hardcoded in the bytecode.
/// Unlike DrawSpritePolygon this is likely intended for drawing backgrounds,
/// since the polygons cannot be scaled or repositioned programmatically.
pub const Instance = struct {
    /// The address within the currently-loaded polygon resource from which to read polygon data.
    address: Video.PolygonAddress,
    /// The X and Y position in screen space at which to draw the polygon.
    point: Point.Instance,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub inline fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        try machine.drawPolygon(.polygons, self.address, self.point, null);
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, not including the opcode itself.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    var self: Instance = undefined;

    // Unlike all other instructions except DrawSpritePolygon, this instruction reuses bits from
    // the original opcode: the polygon address is constructed by combining the lowest 7 bits
    // of the opcode with the next 8 bits from the rest of the bytecode.
    // The combined value is then right-shifted to knock off the highest bit, which is always 1
    // (since that bit indicated this was a DrawBackgroundPolygon operation in the first place:
    // see types/opcode.zig).
    // Since the lowest bit will always be zero as a result, polygons must therefore start
    // on even address boundaries within Another World's polygon resources.
    const high_byte: Video.PolygonAddress = raw_opcode;
    const low_byte: Video.PolygonAddress = try program.read(u8);
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

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    pub const low_x = [_]u8{ 0b1000_1111, 0b0000_1111, 30, 40 };
    pub const high_x = [_]u8{ 0b1000_1111, 0b0000_1111, 255, 240 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses bytecode with low X coordinate and consumes 3 bytes after opcode" {
    const instruction = try expectParse(parse, &BytecodeExamples.low_x, 3);

    // Address will be the first two bytes right-shifted by 1
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(30, instruction.point.x);
    testing.expectEqual(40, instruction.point.y);
}

test "parse parses bytecode with high X coordinate and consumes 3 bytes after opcode" {
    const instruction = try expectParse(parse, &BytecodeExamples.high_x, 3);

    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(255 + (240 - 199), instruction.point.x);
    testing.expectEqual(199, instruction.point.y);
}

test "execute calls drawPolygon with correct parameters" {
    const instruction = Instance{
        .address = 0xDEAD,
        .point = .{ .x = 320, .y = 200 },
    };

    const Stubs = struct {
        var call_count: usize = 0;

        pub fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) void {
            call_count += 1;
            testing.expectEqual(.polygons, source);
            testing.expectEqual(0xDEAD, address);
            testing.expectEqual(320, point.x);
            testing.expectEqual(200, point.y);
            testing.expectEqual(null, scale);
        }
    };

    var machine = MockMachine.new(Stubs);

    try instruction._execute(&machine);

    testing.expectEqual(1, Stubs.call_count);
}
