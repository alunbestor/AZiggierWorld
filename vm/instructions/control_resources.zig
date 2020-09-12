const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const ResourceID = @import("../types/resource_id.zig");
const GamePart = @import("../types/game_part.zig");

const print = @import("std").debug.print;

/// An instruction that loads individual resources and new game parts into memory.
pub const Instance = union(enum) {
    /// Unload all loaded resources and stop audio.
    unload_all,

    /// Load all resources for the specified game part and begin executing its program.
    load_game_part: GamePart.Enum,

    /// Load the specified resource individually.
    load_resource: ResourceID.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        switch (self) {
            .unload_all => print("\nControlResources: unload all resources\n", .{}),
            .load_game_part => |game_part| print("\nControlResources: load game part {X}\n", .{ @enumToInt(game_part) }),
            .load_resource => |resource_id| print("\nControlResources: load resource {X}\n", .{ resource_id }),
        }
    }
};

pub const Error = Program.Error;

pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id_or_game_part = try program.read(ResourceID.Raw);
    
    if (resource_id_or_game_part == 0) {
        return .unload_all;
    } else if (GamePart.parse(resource_id_or_game_part)) |game_part| {
        return Instance { .load_game_part = game_part };
    } else |_err| {
        // If it can't be parsed as a game part, assume it's a resource ID
        return Instance { .load_resource = resource_id_or_game_part };
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlResources);

    pub const unload_all = [_]u8 { raw_opcode, 0x0, 0x0 };
    pub const load_game_part = [_]u8 { raw_opcode, 0x3E, 0x85 }; // GamePart.Enum.arena_cinematic
    pub const load_resource = [_]u8 { raw_opcode, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses unload_all instruction and consumes 2 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.unload_all, 2);
    
    testing.expectEqual(.unload_all, instruction);
}

test "parse parses load_game_part instruction and consumes 2 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.load_game_part, 2);
    
    testing.expectEqual(.{ .load_game_part = .arena_cinematic }, instruction);
}

test "parse parses load_resource instruction and consumes 2 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.load_resource, 2);
    
    testing.expectEqual(.{ .load_resource = 0xDEAD }, instruction);
}

test "execute with unload_all instruction runs on machine without errors" {
    const instruction = Instance.unload_all;
    var machine = Machine.new();
    instruction.execute(&machine);
}

test "execute with load_game_part instruction runs on machine without errors" {
    const instruction = Instance { .load_game_part = .copy_protection };
    var machine = Machine.new();
    instruction.execute(&machine);
}

test "execute with load_resource instruction runs on machine without errors" {
    const instruction = Instance { .load_resource = 0xBEEF };
    var machine = Machine.new();
    instruction.execute(&machine);
}
