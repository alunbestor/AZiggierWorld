const Machine = @import("../machine/machine.zig");
const Host = @import("../machine/host.zig");
const ResourceDirectory = @import("../resources/resource_directory.zig");
const BufferID = @import("../values/buffer_id.zig");
const Video = @import("../machine/video.zig");
const GameInput = @import("../machine/user_input.zig");

const SDL = @import("sdl2");
const std = @import("std");
const log = @import("../utils/logging.zig").log;

const Input = struct {
    game_input: GameInput.Instance = .{},
    turbo: bool = false,
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
                    .space => self.game_input.action = true,
                    .@"return" => self.game_input.action = true,
                    .delete, .backspace => self.turbo = true,

                    else => {},
                }
            },

            .key_up => |key_event| {
                switch (key_event.keycode) {
                    .left => self.game_input.left = false,
                    .right => self.game_input.right = false,
                    .down => self.game_input.down = false,
                    .up => self.game_input.up = false,
                    .space => self.game_input.action = false,
                    .@"return" => self.game_input.action = false,
                    .delete, .backspace => self.turbo = false,

                    else => {},
                }
            },

            else => {},
        }
    }

    // Clear the state of inputs that should register as discrete keypresses
    // rather than being held down continuously. Should be called at the end
    // of each tic, after the input has been consumed by the virtual machine.
    fn clearPressedInputs(self: *Self) void {
        self.game_input.show_password_screen = false;
        self.game_input.last_pressed_character = null;
    }
};

pub const Instance = struct {
    allocator: std.mem.Allocator,

    game_dir: std.fs.Dir,
    resource_directory: ResourceDirectory.Instance,
    machine: Machine.Instance,

    window: SDL.Window,
    renderer: SDL.Renderer,
    texture: SDL.Texture,

    /// The moment at which the previous frame was rendered.
    /// Used for adjusting frame delays to account for processing time.
    last_frame_time: ?i64 = null,
    input: Input = .{},

    const Self = @This();

    /// Heap-allocate a new game engine that loads data from the specified path.
    pub fn init(allocator: std.mem.Allocator, game_path: []const u8) !*Instance {
        // FIXME: I needed to heap-allocate this instead of just returning the struct,
        // because it stores pointers to itself (the resource directory's reader interface
        // and the host interface) and for some reason the return from this function was
        // copying the struct instead of filling its data into the return location.
        // We can revisit this once Zig supports move-only types/variables.
        var self: *Self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;

        // - Load game resources and initialize virtual machine -

        self.game_dir = try std.fs.cwd().openDir(game_path, .{});
        errdefer self.game_dir.close();

        self.resource_directory = try ResourceDirectory.new(&self.game_dir);

        self.machine = try Machine.new(
            allocator,
            self.resource_directory.reader(),
            self.host(),
            .{ .initial_game_part = .intro_cinematic },
        );
        errdefer self.machine.deinit();

        // - Initialize SDL -

        try SDL.init(.{
            .video = true,
            .events = true,
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

        // ABGR888 produces a single-plane pixel buffer where each sequence of 4 bytes
        // matches the byte layout of our RGBA color struct on little-endian architectures.
        // We may need to swap this out for .rgba8888 on big-endian, as internally SDL seems
        // to parse those sequences as 32-bit integers.
        self.texture = try SDL.createTexture(self.renderer, .abgr8888, .streaming, 320, 200);
        errdefer self.texture.destroy();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.texture.destroy();
        self.renderer.destroy();
        self.window.destroy();
        SDL.quit();

        self.machine.deinit();
        self.game_dir.close();

        self.allocator.destroy(self);
    }

    fn host(self: *Self) Host.Interface {
        return Host.Interface.init(self, bufferReady);
    }

    // - VM execution

    pub fn runUntilExit(self: *Self) !void {
        self.input = .{};

        while (true) {
            while (SDL.pollEvent()) |event| {
                self.input.updateFromSDLEvent(event);
            }
            if (self.input.exited) break;

            try self.machine.runTic(self.input.game_input);

            self.input.clearPressedInputs();
        }
    }

    fn nanosecondsSinceLastFrame(self: Self) ?u64 {
        // TODO: switch to using std.time.Instant once we're past 0.9.1.
        if (self.last_frame_time) |last_frame_time| {
            const current_time = @truncate(i64, std.time.nanoTimestamp());
            if (std.math.cast(u64, current_time - last_frame_time)) |elapsed_time| {
                return elapsed_time;
            } else |_| {
                // Ignore negative timestamps
                return null;
            }
        } else {
            // This is the first frame
            return null;
        }
    }

    fn bufferReady(self: *Self, machine: *const Machine.Instance, buffer_id: BufferID.Specific, requested_delay: Host.Milliseconds) void {
        const requested_delay_in_ns = requested_delay * std.time.ns_per_ms;
        var resolved_delay = requested_delay_in_ns;

        // Fast-forward when turbo mode is active.
        if (self.input.turbo) {
            resolved_delay = 0;
        }

        // Reduce the delay by the time elapsed since the previous frame.
        if (self.nanosecondsSinceLastFrame()) |elapsed_time| {
            // Saturating subtraction: minimum of 0
            resolved_delay -|= elapsed_time;
            log.debug("Original delay: {d:.2}ms elapsed time: {d:.2}ms final delay {d:.2}ms", .{
                @intToFloat(f64, requested_delay_in_ns) / std.time.ns_per_ms,
                @intToFloat(f64, elapsed_time) / std.time.ns_per_ms,
                @intToFloat(f64, resolved_delay) / std.time.ns_per_ms,
            });
        } else {
            log.debug("Ignoring elapsed time", .{});
        }

        std.time.sleep(resolved_delay);

        var locked_texture = self.texture.lock(null) catch @panic("self.texture.lock failed");
        const raw_pixels = @ptrCast(*Video.HostSurface, locked_texture.pixels);

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

        self.last_frame_time = @truncate(i64, std.time.nanoTimestamp());
    }
};

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}
