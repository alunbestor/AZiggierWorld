//! Tests that MEMLIST.BIN files from the original Another World are parsed correctly.
//! Requires a `dos_fixture` folder containing Another World DOS game files.

const ResourceLoader = @import("../resources/resource_loader.zig");
const ResourceID = @import("../vm/types/resource_id.zig");

const testing = @import("../utils/testing.zig");
const std = @import("std");

// Relative to the base project folder, not to the location of this source file.
const relative_fixture_path = "integration_tests/fixtures/dos/";

test "ResourceLoader loads all game resources" {
    const game_path = try std.fs.realpathAlloc(testing.allocator, relative_fixture_path);
    defer testing.allocator.free(game_path);

    const loader = try ResourceLoader.new(testing.allocator, game_path);
    defer loader.deinit();

    testing.expectEqual(146, loader.resource_descriptors.len);
    
    // For each resource, test that it can be parsed and decompressed without errors.
    for (loader.resource_descriptors) |descriptor, index| {
        const id = @intCast(ResourceID.Raw, index);
        const data = try loader.readResourceByID(testing.allocator, id);
        defer testing.allocator.free(data);

        testing.expectEqual(descriptor.uncompressed_size, data.len);
    }
}

test "Instance.readResource returns error.OutOfMemory if it runs out of memory when loading a non-empty resource" {
    const game_path = try std.fs.realpathAlloc(testing.allocator, relative_fixture_path);
    defer testing.allocator.free(game_path);

    const loader = try ResourceLoader.new(testing.allocator, game_path);
    defer loader.deinit();
    
    // Some resources are zero-length; testing.failing_allocator would not fail if the memory required is 0.
    const non_empty_descriptor = for (loader.resource_descriptors) |descriptor| {
        if (descriptor.uncompressed_size > 0) { break descriptor; }
    } else { unreachable; };

    testing.expectError(
        error.OutOfMemory,
        loader.readResource(testing.failing_allocator, non_empty_descriptor),
    );
}

test "Instance.readResourceByID returns error.InvalidResourceID when given a resource ID that is out of range" {
    const game_path = try std.fs.realpathAlloc(testing.allocator, relative_fixture_path);
    defer testing.allocator.free(game_path);

    const loader = try ResourceLoader.new(testing.allocator, game_path);
    defer loader.deinit();

    testing.expectError(
        error.InvalidResourceID, 
        loader.readResourceByID(testing.allocator, @intCast(ResourceID.Raw, loader.resource_descriptors.len)),
    );
}