const anotherworld = @import("../../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;

/// Play a sound on a channel, or stop a channel from playing.
pub const ControlSound = union(enum) {
    play: struct {
        /// The ID of the sound to play.
        resource_id: resources.ResourceID,
        /// The channel on which to play the sound.
        channel_id: vm.ChannelID,
        /// The volume at which to play the sound.
        /// TODO: document default volume and observed range.
        volume: audio.Volume.Trusted,
        /// The ID of the preset pitch at which to play the sound.
        frequency_id: audio.FrequencyID,
    },
    stop: vm.ChannelID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const resource_id = resources.ResourceID.cast(try program.read(resources.ResourceID.Raw));
        const frequency_id = try program.read(audio.FrequencyID);
        const raw_volume = try program.read(audio.Volume.Raw);
        const raw_channel_id = try program.read(vm.ChannelID.Raw);

        const volume = try audio.Volume.parse(raw_volume);
        const channel_id = try vm.ChannelID.parse(raw_channel_id);

        if (volume > 0) {
            return Self{
                .play = .{
                    .resource_id = resource_id,
                    .channel_id = channel_id,
                    .volume = volume,
                    .frequency_id = frequency_id,
                },
            };
        } else {
            return Self{ .stop = channel_id };
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *vm.Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playSound(operation.resource_id, operation.channel_id, operation.volume, operation.frequency_id),
            .stop => |channel_id| machine.stopChannel(channel_id),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlSound;
    pub const ParseError = Program.ReadError || vm.ChannelID.Error || audio.Volume.ParseError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = play;

        const play = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0x3F, 0x03 };
        const stop = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0x01 };

        const invalid_channel = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xFF, 0x3F, 0x04 };
        const invalid_volume = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xFF, 0x40, 0x03 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.play, 6);
    const expected = ControlSound{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .channel_id = vm.ChannelID.cast(3),
            .volume = 63,
            .frequency_id = 0xBE,
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.stop, 6);
    const expected = ControlSound{ .stop = vm.ChannelID.cast(1) };
    try testing.expectEqual(expected, instruction);
}

test "parse returns error.VolumeOutOfRange when invalid volume is specified in bytecode" {
    try testing.expectError(
        error.VolumeOutOfRange,
        expectParse(ControlSound.parse, &ControlSound.Fixtures.invalid_volume, 6),
    );
}

test "parse returns error.InvalidChannelID when unknown channel is specified in bytecode" {
    try testing.expectError(
        error.InvalidChannelID,
        expectParse(ControlSound.parse, &ControlSound.Fixtures.invalid_channel, 6),
    );
}

test "execute with play instruction calls playSound with correct parameters" {
    const instruction = ControlSound{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .channel_id = vm.ChannelID.cast(0),
            .volume = 20,
            .frequency_id = 0,
        },
    };

    var machine = mockMachine(struct {
        pub fn playSound(resource_id: resources.ResourceID, channel_id: vm.ChannelID, volume: audio.Volume.Trusted, frequency: audio.FrequencyID) !void {
            try testing.expectEqual(resources.ResourceID.cast(0xDEAD), resource_id);
            try testing.expectEqual(vm.ChannelID.cast(0), channel_id);
            try testing.expectEqual(20, volume);
            try testing.expectEqual(0, frequency);
        }

        pub fn stopChannel(_: vm.ChannelID) void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.playSound);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = ControlSound{ .stop = vm.ChannelID.cast(1) };

    var machine = mockMachine(struct {
        pub fn playSound(_: resources.ResourceID, _: vm.ChannelID, _: audio.Volume.Trusted, _: audio.FrequencyID) !void {
            unreachable;
        }

        pub fn stopChannel(channel_id: vm.ChannelID) void {
            testing.expectEqual(vm.ChannelID.cast(1), channel_id) catch {
                unreachable;
            };
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.stopChannel);
}
