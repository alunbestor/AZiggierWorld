//! A mock equivalent of ResourceDirectory.Instance, intended for unit tests
//! that need to test resource-loading pathways but don't want to depend
//! on the presence of real game files.
//!
//! This mock resource repository provides a configurable list of resource descriptors;
//! attempts to load any descriptor will produce either a configurable error,
//! or a pointer to garbage data of an appropriate length for that resource.
//!
//! Use the `reader()` method to get a Reader interface for loading game data.
//! See reader.zig for the available methods on that interface.
//!
//! Usage:
//! ------
//! const resource_descriptors = []ResourceDescriptor.Instance { descriptor1, descriptor2...descriptorN };
//! const error_to_produce_on_read: ?anyerror = null;
//! var repository = MockRepository.Instance.init(resource_descriptors, error_to_produce_on_read);
//! const reader = repository.reader();
//!
//! const first_resource_descriptor = try reader.resourceDescriptor(0);
//! try testing.expectEqual(0, repository.read_count);
//! const garbage_data = try reader.allocReadResource(testing.allocator, first_resource_descriptor);
//! try testing.expectEqual(1, repository.read_count);

const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");
const Reader = @import("reader.zig");

const static_limits = @import("../static_limits.zig");

const mem = @import("std").mem;
const BoundedArray = @import("std").BoundedArray;

const DescriptorStorage = BoundedArray(ResourceDescriptor.Instance, static_limits.max_resource_descriptors);

pub const Instance = struct {
    /// The list of resources vended by this mock repository.
    /// Access this via reader().resourceDescriptors() instead of directly.
    _raw_descriptors: DescriptorStorage,

    /// An optional error returned by `bufReadResource` to simulate file-reading or decompression errors.
    /// If `null`, `bufReadResource` will return a success response.
    read_error: ?anyerror,

    /// The number of times a resource has been loaded, whether the load succeeded or failed.
    /// Incremented by calls to reader().bufReadResource() or any of its derived methods.
    read_count: usize = 0,

    /// Create a new mock repository that exposes the specified resource descriptors,
    /// and produces either an error or an appropriately-sized buffer full of garbage when
    /// a resource load method is called.
    pub fn init(descriptors: []const ResourceDescriptor.Instance, read_error: ?anyerror) Instance {
        return Instance{
            ._raw_descriptors = DescriptorStorage.fromSlice(descriptors) catch unreachable,
            .read_error = read_error,
        };
    }

    /// Returns a reader interface for loading game data from this repository.
    pub fn reader(self: *Instance) Reader.Interface {
        return Reader.Interface.init(self, bufReadResource, resourceDescriptors);
    }

    /// Leaves the contents of the supplied buffer unchanged, and returns a pointer to the region
    /// of the buffer that would have been filled by resource data in a real implementation.
    /// Returns error.BufferTooSmall if the supplied buffer would not have been large enough
    /// to hold the real resource.
    fn bufReadResource(self: *Instance, buffer: []u8, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        self.read_count += 1;

        if (buffer.len < descriptor.uncompressed_size) {
            return error.BufferTooSmall;
        }

        return self.read_error orelse buffer[0..descriptor.uncompressed_size];
    }

    /// Returns a list of all valid resource descriptors,
    /// loaded from the MEMLIST.BIN file in the game directory.
    fn resourceDescriptors(self: *const Instance) []const ResourceDescriptor.Instance {
        return self._raw_descriptors.constSlice();
    }
};

// -- Resource descriptor fixture data --

pub const FixtureData = struct {
    const empty_descriptor = ResourceDescriptor.Instance{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 0,
        .uncompressed_size = 0,
    };

    const sfx_descriptor = ResourceDescriptor.Instance{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const music_descriptor = ResourceDescriptor.Instance{
        .type = .music,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const bitmap_descriptor = ResourceDescriptor.Instance{
        .type = .bitmap,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 32_000,
        .uncompressed_size = 32_000,
    };

    const palettes_descriptor = ResourceDescriptor.Instance{
        .type = .palettes,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 1024,
        .uncompressed_size = 1024,
    };

    const bytecode_descriptor = ResourceDescriptor.Instance{
        .type = .bytecode,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    const polygons_descriptor = ResourceDescriptor.Instance{
        .type = .polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    const sprite_polygons_descriptor = ResourceDescriptor.Instance{
        .type = .sprite_polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    pub const sfx_resource_id = 0x01;
    pub const music_resource_id = 0x02;
    pub const bitmap_resource_id = 0x03;
    pub const bitmap_resource_id_2 = 0x04;

    /// A list of fake descriptors with realistic values for resources that are referenced in game parts.
    pub const descriptors = block: {
        const max_resource_id = 0x7F;
        var d = [_]ResourceDescriptor.Instance{empty_descriptor} ** (max_resource_id + 1);

        // Drop in individually loadable resources at known offsets
        d[sfx_resource_id] = sfx_descriptor;
        d[music_resource_id] = music_descriptor;
        d[bitmap_resource_id] = bitmap_descriptor;
        d[bitmap_resource_id_2] = bitmap_descriptor;

        // Animation data shared by all game parts
        d[0x11] = sprite_polygons_descriptor;

        // Part-specific data: see game_part.zig

        // GamePart.Enum.copy_protection
        d[0x14] = palettes_descriptor;
        d[0x15] = bytecode_descriptor;
        d[0x16] = polygons_descriptor;

        // GamePart.Enum.intro_cinematic
        d[0x17] = palettes_descriptor;
        d[0x18] = bytecode_descriptor;
        d[0x19] = polygons_descriptor;

        // GamePart.Enum.gameplay1
        d[0x1A] = palettes_descriptor;
        d[0x1B] = bytecode_descriptor;
        d[0x1C] = polygons_descriptor;

        // GamePart.Enum.gameplay2
        d[0x1D] = palettes_descriptor;
        d[0x1E] = bytecode_descriptor;
        d[0x1F] = polygons_descriptor;

        // GamePart.Enum.gameplay3
        d[0x20] = palettes_descriptor;
        d[0x21] = bytecode_descriptor;
        d[0x22] = polygons_descriptor;

        // GamePart.Enum.arena_cinematic
        d[0x23] = palettes_descriptor;
        d[0x24] = bytecode_descriptor;
        d[0x25] = polygons_descriptor;

        // GamePart.Enum.gameplay4
        d[0x26] = palettes_descriptor;
        d[0x27] = bytecode_descriptor;
        d[0x28] = polygons_descriptor;

        // GamePart.Enum.gameplay5
        d[0x29] = palettes_descriptor;
        d[0x2A] = bytecode_descriptor;
        d[0x2B] = polygons_descriptor;

        // GamePart.Enum.password_entry
        d[0x7D] = palettes_descriptor;
        d[0x7E] = bytecode_descriptor;
        d[0x7F] = polygons_descriptor;

        break :block d;
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");

const example_descriptor = ResourceDescriptor.Instance{
    .type = .bytecode,
    .bank_id = 0,
    .bank_offset = 0,
    .compressed_size = 10,
    .uncompressed_size = 10,
};

test "bufReadResource returns slice of original buffer when buffer is appropriate size" {
    var repository = Instance.init(&.{example_descriptor}, null);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size * 2);
    defer testing.allocator.free(buffer);

    try testing.expectEqual(0, repository.read_count);
    const result = try repository.reader().bufReadResource(buffer, example_descriptor);
    try testing.expectEqual(@ptrToInt(result.ptr), @ptrToInt(buffer.ptr));
    try testing.expectEqual(result.len, example_descriptor.uncompressed_size);
    try testing.expectEqual(1, repository.read_count);
}

test "bufReadResource returns supplied error when buffer is appropriate size" {
    var repository = Instance.init(&.{example_descriptor}, error.ChecksumFailed);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size * 2);
    defer testing.allocator.free(buffer);

    try testing.expectEqual(0, repository.read_count);
    try testing.expectError(error.ChecksumFailed, repository.reader().bufReadResource(buffer, example_descriptor));
    try testing.expectEqual(1, repository.read_count);
}

test "bufReadResource returns error.BufferTooSmall if buffer is too small for resource, even if another error was specified" {
    var repository = Instance.init(&.{example_descriptor}, error.ChecksumFailed);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size / 2);
    defer testing.allocator.free(buffer);

    try testing.expectEqual(0, repository.read_count);
    try testing.expectError(error.BufferTooSmall, repository.reader().bufReadResource(buffer, example_descriptor));
    try testing.expectEqual(1, repository.read_count);
}

test "resourceDescriptors returns expected descriptors" {
    var repository = Instance.init(&FixtureData.descriptors, null);

    try testing.expectEqualSlices(ResourceDescriptor.Instance, repository.reader().resourceDescriptors(), &FixtureData.descriptors);
}

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}