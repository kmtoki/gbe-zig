const std = @import("std");

pub const CartrigeType = struct { mbc_type: MBCType, ram: bool, battery: bool, timer: bool };

pub const MBCType = enum { none, mbc1 };

pub const ROM = struct {
    title: []u8,
    manufacturer_code: []u8,
    cgb_flag: u8,
    new_licensee_code: []u8,
    sgb_flag: u8,
    cartrige_type: CartrigeType,
    rom_size: usize,
    ram_size: usize,
    destination_code: u8,
    old_licensee_code: u8,
    mask_rom_version_number: u8,
    header_checksum: u8,
    global_checksum: u16,

    data: []u8,

    pub fn parse(data: []u8) ROM {
        return .{
            .title = data[0x134..0x143],
            .manufacturer_code = data[0x13f..0x142],
            .cgb_flag = data[0x143],
            .new_licensee_code = data[0x144..0x145],
            .sgb_flag = data[0x146],
            .cartrige_type = switch (data[0x147]) {
                0x00 => .{ .mbc_type = .none, .ram = false, .battery = false, .timer = false },
                0x01 => .{ .mbc_type = .mbc1, .ram = false, .battery = false, .timer = false },
                0x02 => .{ .mbc_type = .mbc1, .ram = true, .battery = false, .timer = false },
                0x03 => .{ .mbc_type = .mbc1, .ram = true, .battery = true, .timer = false },
                0x08 => .{ .mbc_type = .none, .ram = true, .battery = false, .timer = false },
                0x09 => .{ .mbc_type = .none, .ram = true, .battery = true, .timer = false },
                else => .{ .mbc_type = .none, .ram = false, .battery = false, .timer = false }
            },
            .rom_size = 0x8000 * (@as(usize,1) << @intCast(u6,data[0x148])),
            .ram_size = switch (data[0x149]) {
                0x0 => 0,
                0x1 => 0,
                0x2 => 0x2000,
                0x3 => 0x8000,
                0x4 => 0x20000,
                0x5 => 0x10000,
                else => 0
            },
            .destination_code = data[0x14a],
            .old_licensee_code = data[0x14b],
            .mask_rom_version_number = data[0x14c],
            .header_checksum = data[0x14d],
            .global_checksum = (@intCast(u16,data[0x14e]) << 8) | @intCast(u16,data[0x14e]),

            .data = data
        };
    }

    pub fn readFile(allocator: std.mem.Allocator, path: []const u8) !ROM {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();
        const stat = try file.stat();
        const buffer = try file.reader().readAllAlloc(allocator,stat.size);

        return parse(buffer);
    }
};

