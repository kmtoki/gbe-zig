const std = @import("std");
const fs = std.fs;

const print = std.debug.print;

pub const Logger = struct {
    is_print: bool,
    is_dump: bool,
    pos: usize,
    buffer: [0xfffff]u8,
    path: []const u8,
    file: ?fs.File,

    pub fn init() !Logger {
        var self = Logger{
            .is_print = false,
            .is_dump = false,
            .path = "./log.txt",
            .buffer = [1]u8{0} ** 0xfffff,
            .pos = 0,
            .file = null,
        };
        if (self.is_dump) {
            try self.createFile(null);
        }
        return self;
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| file.close();
    }

    pub fn createFile(self: *Logger, path: ?[]const u8) fs.File.OpenError!void {
        if (path) |p| {
            self.path = p;
        }
        self.is_dump = true;
        self.file = try fs.cwd().createFile(self.path, .{});
    }

    pub fn flush(self: *Logger) fs.File.WriteError!void {
        if (self.is_dump) {
            if (self.file) |file| {
                var end: usize = 0xfffff - 1;
                while (0 < end) : (end -= 1) {
                    if (self.buffer[end] != 0) break;
                }

                try file.writeAll(self.buffer[0 .. end]);
            }
        }
        self.pos = 0;
        self.buffer = [1]u8{0} ** 0xfffff;
    }

    pub fn log(self: *Logger, str: []u8) void {
        if (self.is_print) {
            print("{s}\n", .{str});
        }

        if (self.pos + str.len >= 0xfffff) {
            self.flush() catch {};
        }

        for (str) |c| {
            if (c == 0) {
                self.buffer[self.pos] = '\n';
                self.pos += 1;
                break;
            }
            self.buffer[self.pos] = c;
            self.pos += 1;
        }

        //std.mem.copy(u8, self.buffer[self.pos .. self.pos + str.len], str);
        //self.pos += str.len;
    }

    pub fn logFmt(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        var buf = [1]u8{0} ** 1000;
        _ = std.fmt.bufPrint(&buf, fmt, args) catch {};
        self.log(&buf);
    }
};
