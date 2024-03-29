//! This test dumps data about the sizes of each game part's data
//! in the fixture directory.

const anotherworld = @import("anotherworld");
const resources = anotherworld.resources;
const vm = anotherworld.vm;
const log = anotherworld.log;

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;
const testing = @import("utils").testing;

const std = @import("std");

test "Report sizes for each game part" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    // Uncomment to print out statistics
    // testing.setLogLevel(.info);

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    var max_bytecode_size: usize = 0;
    var max_palettes_size: usize = 0;
    var max_polygons_size: usize = 0;
    var max_animations_size: usize = 0;

    for (vm.GamePart.all) |part| {
        const resource_ids = part.resourceIDs();

        log.info("\nPart: {s}\n----\n", .{@tagName(part)});

        var total_size: usize = 0;
        const bytecode = try reader.resourceDescriptor(resource_ids.bytecode);
        log.info("bytecode: #{}, {} bytes\n", .{ resource_ids.bytecode, bytecode.uncompressed_size });
        total_size += bytecode.uncompressed_size;
        max_bytecode_size = @maximum(max_bytecode_size, bytecode.uncompressed_size);

        const palettes = try reader.resourceDescriptor(resource_ids.palettes);
        log.info("palette: #{}, {} bytes", .{ resource_ids.palettes, palettes.uncompressed_size });
        total_size += palettes.uncompressed_size;
        max_palettes_size = @maximum(max_palettes_size, palettes.uncompressed_size);

        const polygons = try reader.resourceDescriptor(resource_ids.polygons);
        log.info("polygons: #{}, {} bytes", .{ resource_ids.polygons, polygons.uncompressed_size });
        total_size += polygons.uncompressed_size;
        max_polygons_size = @maximum(max_polygons_size, polygons.uncompressed_size);

        if (resource_ids.animations) |animation_id| {
            const animations = try reader.resourceDescriptor(animation_id);
            log.info("animations: #{}, {} bytes", .{ animation_id, animations.uncompressed_size });
            total_size += animations.uncompressed_size;
            max_animations_size = @maximum(max_animations_size, animations.uncompressed_size);
        } else {
            log.info("animations: UNUSED", .{});
        }
        log.info("----\ntotal size: {} bytes", .{total_size});

        log.info("\n====", .{});
    }

    log.info("\nMax sizes:\n----", .{});
    log.info("bytecode: {} bytes", .{max_bytecode_size});
    log.info("palettes: {} bytes", .{max_palettes_size});
    log.info("polygons: {} bytes", .{max_polygons_size});
    log.info("animations: {} bytes", .{max_animations_size});

    const max_total_size = max_bytecode_size + max_palettes_size + max_polygons_size + max_animations_size;
    log.info("----\nmax possible size for game part: {} bytes\n", .{max_total_size});
}
