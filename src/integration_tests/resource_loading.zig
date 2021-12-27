//! Tests that ResourceDirectory correctly parses real game files from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const ResourceDirectory = @import("../resources/resource_directory.zig");
const ResourceID = @import("../values/resource_id.zig");

const testing = @import("../utils/testing.zig");
const validFixtureDir = @import("helpers.zig").validFixtureDir;
const log = @import("std").log;

test "ResourceDirectory reads all game resources" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const repository = resource_directory.repository();

    const descriptors = repository.resourceDescriptors();
    try testing.expectEqual(146, descriptors.len);

    // For each resource, test that it can be parsed and decompressed without errors.
    for (descriptors) |descriptor| {
        const data = try repository.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        try testing.expectEqual(descriptor.uncompressed_size, data.len);
    }
}

test "Instance.readResourceAlloc returns error.OutOfMemory if it runs out of memory when loading a non-empty resource" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const repository = resource_directory.repository();

    // Some resources are zero-length; testing.failing_allocator would not fail if the memory required is 0.
    const non_empty_descriptor = for (repository.resourceDescriptors()) |descriptor| {
        if (descriptor.uncompressed_size > 0) {
            break descriptor;
        }
    } else {
        log.warn("\nNo non-empty resources found in game directory, skipping test. This probably indicates a corrupted version of the game.\n", .{});
        return;
    };

    try testing.expectError(
        error.OutOfMemory,
        repository.allocReadResource(testing.failing_allocator, non_empty_descriptor),
    );
}

test "Instance.allocReadResourceByID returns error.InvalidResourceID when given a resource ID that is out of range" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const repository = resource_directory.repository();

    const invalid_id = @intCast(ResourceID.Raw, repository.resourceDescriptors().len);
    try testing.expectError(
        error.InvalidResourceID,
        repository.allocReadResourceByID(testing.allocator, invalid_id),
    );
}
