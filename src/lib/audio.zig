//! This namespace will eventually define the audio subsystem responsible for sound and music playback.

pub const Delay = u16;
pub const Offset = u8;

pub const Volume = @import("audio/volume.zig");

pub const FrequencyID = u8;
pub const Frequency = u16;

pub const SoundResource = @import("audio/sound_resource.zig").SoundResource;
pub const MusicResource = @import("audio/music_resource.zig").MusicResource;
