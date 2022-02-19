//! Measures the performance of a block of code by executing it multiple times
//! and sampling each iteration.
//! Messily adapted from https://github.com/ziglang/gotta-go-fast.

const std = @import("std");

/// The result of a measure operation.
pub const Result = struct {
    /// The total number of iterations.
    iterations: usize,
    /// The total time spent executing all iterations, in nanoseconds.
    total_execution_time: u64,
    /// The minimum time a single iteration took, in nanoseconds.
    min_iteration_time: u64,
    /// The maximum time a single iteration took, in nanoseconds.
    max_iteration_time: u64,
    /// The mean time a single iteration took, in nanoseconds.
    mean_iteration_time: u64,
    /// The median time a single iteration took, in nanoseconds.
    median_iteration_time: u64,

    /// Print the results in a human-readable format.
    pub fn format(self: Result, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer,
            \\Iterations: {} within time limit
            \\Total execution time: {}nsec
            \\Min iteration time: {}nsec
            \\Max iteration time: {}nsec
            \\Mean iteration time: {}nsec
            \\Median iteration time: {}nsec
        , .{
            self.iterations,
            self.total_execution_time,
            self.min_iteration_time,
            self.max_iteration_time,
            self.mean_iteration_time,
            self.median_iteration_time,
        });
    }
};

/// Execute a specific function for n iterations, measuring the mean and median time taken
/// to execute the function.
///
/// Parameters:
/// subject: A struct whose execute() function implements the behavior that should be measured.
/// max_iterations: The number of times to run the subject's execute() function. Must be at least 3.
/// max_duration: The maximum time in nanoseconds to run the measurement for.
///
/// Returns: A Result struct describing the min, max and average times of the iterations.
pub fn measure(subject: anytype, comptime max_iterations: usize, max_duration: u64) !Result {
    const min_iterations = 3;

    // We throw away the fastest and slowest samples, so we need at least 1 other iteration on top of those.
    std.debug.assert(max_iterations >= min_iterations);

    var timer = try std.time.Timer.start();
    const start = timer.read();

    var all_samples: [max_iterations]u64 = undefined;
    var total_iterations: usize = 0;

    for (all_samples) |*sample| {
        const lap_start = timer.read();

        try subject.execute();

        const lap_end = timer.read();

        sample.* = lap_end - lap_start;
        total_iterations += 1;

        // Break early if we hit the maximum time before hitting the maximum iterations
        if (total_iterations >= min_iterations and lap_end - start >= max_duration) break;
    }

    const used_samples = all_samples[0..total_iterations];
    std.sort.sort(u64, used_samples, {}, comptime std.sort.asc(u64));

    // Discard lowest and highest samples to allow for system noise
    const usable_samples = used_samples[1 .. used_samples.len - 1];

    var total_execution_time: u64 = 0;
    var min_iteration_time: u64 = std.math.maxInt(u64);
    var max_iteration_time: u64 = 0;

    for (usable_samples) |sample| {
        total_execution_time += sample;
        if (sample < min_iteration_time) min_iteration_time = sample;
        if (sample > max_iteration_time) max_iteration_time = sample;
    }

    const median = usable_samples[usable_samples.len / 2];
    const mean = total_execution_time / usable_samples.len;

    return Result{
        .iterations = total_iterations,
        .total_execution_time = total_execution_time,
        .min_iteration_time = min_iteration_time,
        .max_iteration_time = max_iteration_time,
        .mean_iteration_time = mean,
        .median_iteration_time = median,
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(@This());
}
