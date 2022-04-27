//! Looks up polygon draw instructions from bytecode and tests that the corresponding
//! polygon addresses can be parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const Instruction = @import("../instructions/instruction.zig");
const Program = @import("../machine/program.zig").Program;
const PolygonResource = @import("../resources/polygon_resource.zig").PolygonResource;
const Polygon = @import("../rendering/polygon.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const Point = @import("../values/point.zig");
const ResourceDirectory = @import("../resources/resource_directory.zig").ResourceDirectory;
const GamePart = @import("../values/game_part.zig");
const DrawBackgroundPolygon = @import("../instructions/draw_background_polygon.zig").DrawBackgroundPolygon;
const DrawSpritePolygon = @import("../instructions/draw_sprite_polygon.zig").DrawSpritePolygon;

const testing = @import("../utils/testing.zig");
const log = @import("../utils/logging.zig").log;
const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;
const std = @import("std");

const PolygonDrawInstruction = union(enum) {
    background: DrawBackgroundPolygon,
    sprite: DrawSpritePolygon,
};

/// Parses an Another World bytecode program to find all the draw instructions in it.
/// Returns an array of draw instructions which is owned by the caller.
/// Returns an error if parsing or memory allocation failed.
fn findPolygonDrawInstructions(allocator: std.mem.Allocator, bytecode: []const u8) ![]const PolygonDrawInstruction {
    var instructions = std.ArrayList(PolygonDrawInstruction).init(allocator);
    errdefer instructions.deinit();

    var program = Program.init(bytecode);
    while (program.isAtEnd() == false) {
        switch (try Instruction.parseNextInstruction(&program)) {
            .DrawBackgroundPolygon => |instruction| {
                try instructions.append(.{ .background = instruction });
            },
            .DrawSpritePolygon => |instruction| {
                try instructions.append(.{ .sprite = instruction });
            },
            else => {},
        }
    }

    return instructions.toOwnedSlice();
}

/// Parses all polygon draw instructions from the bytecode for a given game part,
/// then parses the polygons themselves from the respective polygon or animation resource for that game part.
/// Returns the total number of polygons parsed, or an error if parsing or memory allocation failed.
fn parsePolygonInstructionsForGamePart(allocator: std.mem.Allocator, resource_directory: *ResourceDirectory, game_part: GamePart.Enum) !usize {
    const resource_ids = game_part.resourceIDs();
    const reader = resource_directory.reader();

    const bytecode = try reader.allocReadResourceByID(allocator, resource_ids.bytecode);
    defer allocator.free(bytecode);

    const instructions = try findPolygonDrawInstructions(allocator, bytecode);
    defer allocator.free(instructions);

    const polygons = PolygonResource.init(try reader.allocReadResourceByID(allocator, resource_ids.polygons));
    defer allocator.free(polygons.data);

    const maybe_animations: ?PolygonResource = init: {
        if (resource_ids.animations) |id| {
            const data = try reader.allocReadResourceByID(allocator, id);
            break :init PolygonResource.init(data);
        } else {
            break :init null;
        }
    };

    defer {
        if (maybe_animations) |animations| {
            allocator.free(animations.data);
        }
    }

    var visitor = PolygonVisitor{};

    // TODO: once the draw instructions have been refactored to use Video.Instance,
    // execute them directly on a virtual machine to trigger real polygon parsing and drawing.
    for (instructions) |background_or_sprite| {
        switch (background_or_sprite) {
            .background => |instruction| {
                try polygons.iteratePolygons(instruction.address, instruction.point, PolygonScale.default, &visitor);
            },
            .sprite => |instruction| {
                const resource = switch (instruction.source) {
                    .polygons => polygons,
                    .animations => maybe_animations orelse return error.MissingAnimationsBlock,
                };
                // Don't bother parsing the scale or origin from the original sprite instruction.
                const origin = Point.Instance{ .x = 160, .y = 100 };

                try resource.iteratePolygons(instruction.address, origin, PolygonScale.default, &visitor);
            },
        }
    }

    return visitor.count;
}

const Error = error{
    /// A game part's draw instructions tried to draw polygon data from the `animations` block
    /// when one is not defined for that game part.
    MissingAnimationsBlock,
};

const PolygonVisitor = struct {
    count: usize = 0,

    pub fn visit(self: *PolygonVisitor, polygon: Polygon.Instance) !void {
        self.count += 1;
        try polygon.validate();
    }
};

test "Parse polygon instructions for every game part" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.init(&game_dir);

    var count: usize = 0;
    for (GamePart.Enum.all) |game_part| {
        count += try parsePolygonInstructionsForGamePart(testing.allocator, &resource_directory, game_part);
    }

    log.info("\n{} polygon(s) successfully parsed.\n", .{count});
}
