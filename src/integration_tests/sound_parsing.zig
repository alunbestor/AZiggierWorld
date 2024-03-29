//! Tests that sound effects are correctly parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const audio = anotherworld.audio;
const resources = anotherworld.resources;
const log = anotherworld.log;

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const testing = @import("utils").testing;

test "Parse all sound effects in original game files" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    // Uncomment to print out statistics
    // testing.setLogLevel(.debug);

    for (reader.resourceDescriptors()) |descriptor, id| {
        if (descriptor.type != .sound_or_empty) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        if (audio.SoundResource.parse(data)) |sound| {
            if (sound.loop.len > 0) {
                log.debug("Sound with length {}, looping at {}", .{ sound.intro.len + sound.loop.len, sound.intro.len });
            } else {
                log.debug("Sound with length {}, unlooped", .{sound.intro.len});
            }
        } else |err| {
            if (err == error.TruncatedData and data.len == 0) {
                log.debug("0-length sound effect at {}", .{id});
            } else {
                return err;
            }
        }
    }
}

test "Parse all music in original game files" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    // Uncomment to print out statistics
    // testing.setLogLevel(.debug);

    for (reader.resourceDescriptors()) |descriptor, id| {
        if (descriptor.type != .music) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        const music = try audio.MusicResource.parse(data);

        log.debug("Parsing music #{} (tempo {}, {} patterns in sequence)", .{ id, music.tempo, music.sequence.len });
        var sequence_iterator = try music.iterateSequence(0);
        while (sequence_iterator.next()) |pattern_id| {
            log.debug("Iterating pattern #{}", .{pattern_id});
            var iterator = try music.iteratePattern(pattern_id);

            while (try iterator.next()) |_| {}
        }
    }
}
