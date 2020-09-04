
/// The possible errors from a Writer.
pub const Error = error {
    /// The write buffer ran out of room in the destination buffer before decoding was completed.
    WriteBufferFull,
    /// The write buffer attempted to copy bytes from outside the destination buffer.
    CopyOutOfRange,
};

/// Create a new writer that will begin writing to the end of the specified destination buffer.
pub fn new(destination: []u8) Instance {
    return Instance { 
        .destination = destination,
        .cursor = destination.len
    };
}

/// The byte-wise writer for the run-length decoder. This writing decompressed bytes
/// to a destination buffer, starting from the end of the buffer and working its way forward.
pub const Instance = struct {
    /// The destination buffer to write to.
    destination: []u8,

    /// The current position of the reader within `destination`.
    /// Starts at the end of the destination buffer and works backward from there.
    /// Note that the cursor is 1 higher than you may expect: e.g. when the cursor is 4, 
    /// destination[3] is the next byte to be written.
    cursor: usize,

    /// Write a single byte to the cursor at the current offset.
    pub fn writeByte(self: *Writer, byte: u8) Error!void {
        if (self.isAtEnd()) {
            return error.WriteBufferFull;
        }

        self.cursor -= 1;
        self.destination[self.cursor] = byte;
    }

    /// Read a sequence of bytes working backwards from a location in the destination relative
    // to the current cursor, and write them to the destination starting at the current cursor.
    /// The copied bytes will be in the same order they appeared in the original sequence.
    pub fn copyBytes(self: *Writer, count: usize, offset: usize) Error!void {
        var bytes_remaining: usize = count;
        while (bytes_remaining > 0) : (bytes_remaining -= 1) {
            // -1 accounts for the fact that our internal cursor is at the "end" of the byte,
            // and is only decremented once we write the byte.
            // The offset we get from Another World's data files assume the cursor indicates
            // the start of the byte.
            const index = self.cursor + offset - 1;
            
            if (index >= self.destination.len) {
                return error.CopyOutOfRange;
            }

            try self.writeByte(self.destination[index]);
        }
    }

    pub inline fn isAtEnd(self: Writer) bool {
        return self.cursor <= 0;
    }
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "writeByte writes a single byte starting at the end of the destination" {
    var destination: [4]u8 = undefined;

    var writer = new(&destination);
    testing.expect(!writer.isAtEnd());

    try writer.writeByte(0xDE);
    try writer.writeByte(0xAD);
    try writer.writeByte(0xBE);
    try writer.writeByte(0xEF);

    testing.expect(writer.isAtEnd());

    const expected = [_]u8 { 0xEF, 0xBE, 0xAD, 0xDE };
    testing.expectEqualSlices(u8, &expected, &destination);
}

test "writeByte returns error.WriteBufferFull once destination is full" {
    var destination: [2]u8 = undefined;

    var writer = new(&destination);

    try writer.writeByte(0xDE);
    try writer.writeByte(0xAD);
    
    testing.expectError(error.WriteBufferFull, writer.writeByte(0xBE));
    testing.expect(writer.isAtEnd());
}

test "copyBytes copies bytes from location in destination relative to current cursor" {
    var destination = [_]u8 { 0 } ** 8;

    var writer = new(&destination);

    // Populate the destination with 4 bytes of initial data.
    try writer.writeByte(0xDE);
    try writer.writeByte(0xAD);
    try writer.writeByte(0xBE);
    try writer.writeByte(0xEF);

    const expected_after_write = [_]u8 {
        0x00, 0x00, 0x00, 0x00,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    testing.expectEqualSlices(u8, &expected_after_write, &destination);

    // Copy the last byte (4 bytes ahead of the write cursor)
    try writer.copyBytes(1, 4);

    const expected_after_first_copy = [_]u8 {
        0x00, 0x00, 0x00, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    testing.expectEqualSlices(u8, &expected_after_first_copy, &destination);

    // Copy the last two bytes (the second of which is now 5 bytes ahead of write cursor)
    try writer.copyBytes(2, 5);

    const expected_after_second_copy = [_]u8 {
        0x00, 0xAD, 0xDE, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    testing.expectEqualSlices(u8, &expected_after_second_copy, &destination);

    // Copy the 4th-to-last byte (which is now 4 bytes ahead of write cursor)
    try writer.copyBytes(1, 4);
    testing.expect(writer.isAtEnd());

    const expected_after_third_copy = [_]u8 {
        0xEF, 0xAD, 0xDE, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    testing.expectEqualSlices(u8, &expected_after_third_copy, &destination);
}

test "copyBytes returns error.WriteBufferFull when writing too many bytes" {
    var destination: [5]u8 = undefined;

    var writer = new(&destination);
    testing.expectEqual(5, writer.cursor);

    try writer.writeByte(0xDE);
    try writer.writeByte(0xAD);
    try writer.writeByte(0xBE);
    try writer.writeByte(0xEF);
    testing.expectEqual(1, writer.cursor);

    testing.expectError(error.WriteBufferFull, writer.copyBytes(2, 2));
    testing.expectEqual(0, writer.cursor);
}

test "copyBytes returns error.CopyOutOfRange when offset is out of range" {
    var destination: [8]u8 = undefined;

    var writer = new(&destination);
    testing.expectEqual(8, writer.cursor);

    try writer.writeByte(0xDE);
    try writer.writeByte(0xAD);
    try writer.writeByte(0xBE);
    try writer.writeByte(0xEF);

    testing.expectError(error.CopyOutOfRange, writer.copyBytes(1, 5));
}