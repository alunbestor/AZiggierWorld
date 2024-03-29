const anotherworld = @import("../lib/anotherworld.zig");
const resources = anotherworld.resources;
const log = anotherworld.log;
const vm = anotherworld.vm;

const SDL = @import("sdl2");
const std = @import("std");

const Input = struct {
    game_input: vm.UserInput = .{},
    turbo: bool = false,
    paused: bool = false,
    exited: bool = false,

    const Self = @This();

    fn updateFromSDLEvent(self: *Self, event: SDL.Event) void {
        switch (event) {
            .quit => self.exited = true,

            .key_down => |key_event| {
                // Record the last-pressed ASCII character for text entry on the password screen.
                // SDL keycodes map to ASCII codes for letters of the alphabet,
                // but non-alphabetical keys may have codes larger than will fit in a u8.
                // We don't want to record keypresses for those characters anyway,
                // so ignore them if we can't cast.
                const raw_keycode = @enumToInt(key_event.keycode);
                self.game_input.last_pressed_character = std.math.cast(u8, raw_keycode) catch null;

                switch (key_event.keycode) {
                    .c => self.game_input.show_password_screen = true,
                    .left => self.game_input.left = true,
                    .right => self.game_input.right = true,
                    .down => self.game_input.down = true,
                    .up => self.game_input.up = true,
                    .space, .@"return" => self.game_input.action = true,
                    .delete, .backspace => self.turbo = true,
                    .pause, .@"p" => self.paused = !self.paused,

                    else => {},
                }
            },

            .key_up => |key_event| {
                switch (key_event.keycode) {
                    .left => self.game_input.left = false,
                    .right => self.game_input.right = false,
                    .down => self.game_input.down = false,
                    .up => self.game_input.up = false,
                    .space, .@"return" => self.game_input.action = false,
                    .delete, .backspace => self.turbo = false,

                    else => {},
                }
            },

            else => {},
        }
    }

    // Clear the state of game inputs that should register as discrete keypresses
    // rather than being held down continuously. Should be called at the end
    // of each tic, after the input has been consumed by the virtual machine.
    fn clearPressedInputs(self: *Self) void {
        self.game_input.show_password_screen = false;
        self.game_input.last_pressed_character = null;
    }
};

pub const SDLEngine = struct {
    allocator: std.mem.Allocator,

    game_dir: std.fs.Dir,
    resource_directory: resources.ResourceDirectory,

    window: SDL.Window,
    renderer: SDL.Renderer,
    texture: SDL.Texture,
    audio_device: SDL.AudioDevice,

    /// The moment at which the previous frame was rendered.
    /// Used for adjusting frame delays to account for processing time.
    last_frame_time: ?i64 = null,

    /// The current state of the player's inputs.
    /// Updated on each tic while the host is running.
    input: Input = .{},

    const Self = @This();

    /// Heap-allocate a new game engine that loads data from the specified path.
    pub fn init(allocator: std.mem.Allocator, game_path: []const u8) !*Self {
        // FIXME: I needed to heap-allocate this instead of just returning the struct,
        // because it stores pointers to itself (the resource directory's reader interface
        // and the host interface) and for some reason the return from this function was
        // copying the struct instead of filling its data into the return location.
        // We can revisit this once Zig supports move-only types/variables.
        const self: *Self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;

        // - Load game resources and initialize virtual machine -

        self.game_dir = try std.fs.cwd().openDir(game_path, .{});
        errdefer self.game_dir.close();

        self.resource_directory = try resources.ResourceDirectory.init(&self.game_dir);

        // - Initialize SDL -

        try SDL.init(.{
            .video = true,
            .events = true,
            .audio = true,
        });
        errdefer SDL.quit();

        self.window = try SDL.createWindow(
            "A Ziggier World",
            .default,
            .default,
            960,
            640,
            .{ .shown = true, .allow_high_dpi = true },
        );
        errdefer self.window.destroy();

        self.renderer = try SDL.createRenderer(self.window, null, .{
            .accelerated = true,
            .present_vsync = true,
        });
        errdefer self.renderer.destroy();

        // .abgr8888 produces a single-plane pixel buffer where each sequence of 4 bytes
        // matches the byte layout of our RGBA color struct on little-endian architectures.
        // We may need to swap this out for .rgba8888 on big-endian, as internally SDL seems
        // to parse those sequences as 32-bit integers.
        self.texture = try SDL.createTexture(self.renderer, .abgr8888, .streaming, 320, 200);
        errdefer self.texture.destroy();

        const audio_result = try SDL.openAudioDevice(.{ .desired_spec = .{
            .sample_rate = vm.DefaultSampleRate,
            .buffer_format = SDL.AudioFormat.s8,
            .channel_count = 1,
            .callback = null,
            .userdata = null,
        } });
        errdefer self.audio_device.close();
        self.audio_device = audio_result.device;

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.texture.destroy();
        self.renderer.destroy();
        self.window.destroy();
        self.audio_device.close();
        SDL.quit();

        self.game_dir.close();

        self.allocator.destroy(self);
    }

    fn host(self: *Self) vm.Host {
        return vm.Host.init(self, .{
            .videoFrameReady = videoFrameReady,
            .audioReady = audioReady,
        });
    }

    // - VM execution

    pub fn runUntilExit(self: *Self) !void {
        self.input = .{};
        self.last_frame_time = null;

        var machine = try vm.Machine.init(
            self.allocator,
            self.resource_directory.reader(),
            self.host(),
            .{ .initial_game_part = .intro_cinematic },
        );
        defer machine.deinit();

        self.audio_device.pause(false);

        while (true) {
            while (SDL.pollEvent()) |event| {
                self.input.updateFromSDLEvent(event);
            }

            if (self.input.exited) break;

            if (self.input.paused) {
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            }

            try machine.runTic(self.input.game_input);

            self.input.clearPressedInputs();
        }

        self.audio_device.pause(true);
        clearQueuedAudio(self.audio_device);
    }

    fn videoFrameReady(self: *Self, machine: *const vm.Machine, buffer_id: vm.ResolvedBufferID, requested_delay: vm.Milliseconds) void {
        const requested_delay_in_ns = requested_delay * std.time.ns_per_ms;
        const current_time_in_ns = currentFrameTime();
        const delay_in_ns = resolvedFrameDelay(
            requested_delay_in_ns,
            self.last_frame_time,
            current_time_in_ns,
            self.input.turbo,
        );
        std.time.sleep(delay_in_ns);

        // log.debug("Requested delay: {} actual delay: {}, elapsed time {}", .{
        //     requested_delay_in_ns,
        //     delay_in_ns,
        //     requested_delay_in_ns - delay_in_ns,
        // });

        self.last_frame_time = currentFrameTime();

        var locked_texture = self.texture.lock(null) catch @panic("self.texture.lock failed");
        const raw_pixels = @ptrCast(*vm.HostSurface, locked_texture.pixels);

        machine.renderBufferToSurface(buffer_id, raw_pixels) catch |err| {
            switch (err) {
                // The Another World intro attempts to render at least 4 times before any palette is selected.
                error.PaletteNotSelected => {
                    log.debug("Skipping frame, palette not loaded", .{});
                    return;
                },
                else => unreachable,
            }
        };
        locked_texture.release();

        self.renderer.copy(self.texture, null, null) catch @panic("self.renderer.copy failed");
        self.renderer.present();
    }

    fn audioReady(self: *Self, _: *const vm.Machine, buffer: vm.AudioBuffer) void {
        if (self.input.turbo) return;
        queueAudio(self.audio_device, buffer) catch unreachable;
    }
};

fn queueAudio(audio_device: SDL.AudioDevice, buffer: vm.AudioBuffer) !void {
    log.debug("Queued audio size: {}", .{SDL.c.SDL_GetQueuedAudioSize(audio_device.id)});

    const result = SDL.c.SDL_QueueAudio(audio_device.id, buffer.ptr, @intCast(u32, buffer.len));
    if (result != 0) return SDL.makeError();
}

fn clearQueuedAudio(audio_device: SDL.AudioDevice) void {
    SDL.c.SDL_ClearQueuedAudio(audio_device.id);
}

/// Returns the current time in nanoseconds, intended for calculating frame delays.
fn currentFrameTime() i64 {
    return @truncate(i64, std.time.nanoTimestamp());
}

fn resolvedFrameDelay(requested_delay: u64, possible_last_frame_time: ?i64, current_time: i64, turbo: bool) u64 {
    if (turbo) {
        return 0;
    } else if (possible_last_frame_time) |last_frame_time| {
        // -| is the saturating subtraction operator, to ensure we don't overflow.
        // both operands are signed so the result may still be negative:
        // that would indicate the frame timestamps were not monotonic.
        // In such a case, ignore the elapsed time and use the requested delay as-is.
        const possibly_negative_elapsed_time = current_time -| last_frame_time;

        if (std.math.cast(u64, possibly_negative_elapsed_time)) |elapsed_time| {
            return requested_delay -| elapsed_time;
        } else |_| {
            return requested_delay;
        }
    } else {
        return requested_delay;
    }
}

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(SDLEngine);
}

test "resolvedFrameDelay returns requested delay minus elapsed time between frames" {
    const delay = resolvedFrameDelay(25, 0, 10, false);
    try testing.expectEqual(15, delay);
}

test "resolvedFrameDelay returns requested delay when no time has elapsed between frames" {
    const delay = resolvedFrameDelay(25, 0, 0, false);
    try testing.expectEqual(25, delay);
}

test "resolvedFrameDelay returns 0 when more time has elapsed between frames than requested delay" {
    const delay = resolvedFrameDelay(25, 0, 50, false);
    try testing.expectEqual(0, delay);
}

test "resolvedFrameDelay returns requested delay when previous frame time is later than current time" {
    const delay = resolvedFrameDelay(25, 50, 0, false);
    try testing.expectEqual(25, delay);
}

test "resolvedFrameDelay returns requested delay when no previous frame time is available" {
    const delay = resolvedFrameDelay(25, null, 50, false);
    try testing.expectEqual(25, delay);
}

test "resolvedFrameDelay returns 0 when turbo mode is active, regardless of requested delay" {
    const delay = resolvedFrameDelay(25, 0, 25, true);
    try testing.expectEqual(0, delay);
}

test "resolvedFrameDelay handles negative timestamps before epoch" {
    const delay = resolvedFrameDelay(25, -1000, -990, false);
    try testing.expectEqual(15, delay);
}

test "resolvedFrameDelay does not trap on enormous positive differences between frame times" {
    const delay = resolvedFrameDelay(25, std.math.minInt(i64), std.math.maxInt(i64), false);
    try testing.expectEqual(0, delay);
}

test "resolvedFrameDelay does not trap on enormous negative differences between frame times" {
    const delay = resolvedFrameDelay(25, std.math.maxInt(i64), std.math.minInt(i64), false);
    try testing.expectEqual(25, delay);
}

test "resolvedFrameDelay does not trap on enormous requested frame time" {
    const delay = resolvedFrameDelay(std.math.maxInt(u64), std.math.minInt(i64), std.math.maxInt(i64), false);
    try testing.expectEqual(std.math.maxInt(u64) - @intCast(u64, std.math.maxInt(i64)), delay);
}
