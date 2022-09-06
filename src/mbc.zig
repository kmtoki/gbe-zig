const std = @import("std");
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const ROM = @import("rom.zig").ROM;
const MBCType = @import("rom.zig").MBCType;
const Registers = @import("utils.zig").Registers;

//pub const MBC = union(MBCType) {
//    none,
//    mbc1: MBC1,
//
//    pub fn init(allocator: Allocator, rom: *const Rom) MBC {
//        return switch (rom.cartrige_type.mbc_type) {
//            .mbc1 => .{ .mbc1 = MBC1.init(allocator, rom) },
//            else => |t| panic("MBC.init: unimplement MBCType {any}", .{t}),
//        };
//    }
//
//    pub fn read(self: *MBC, addr: u16) u8 {
//        return switch (self) {
//            .mbc1 => |mbc1| mbc1.read(addr),
//            else => panic("MBC.read: unimplement MBCType", .{}),
//        };
//    }
//
//    pub fn write(self: *MBC, addr: u16, val: u8) void {
//        switch (self) {
//            .mbc1 => |mbc1| mbc1.write(addr, val),
//            else => panic("MBC.write: unimplement MBCType", .{}),
//        }
//    }
//
//    pub fn bank(self: MBC) usize {
//        return switch (self) {
//            .mbc1 => |mbc1| mbc1.bank,
//            else => panic("MBC.bank: unimplement MBCType", .{}),
//        };
//    }
//};
//
//pub const MBC1 = struct {
//    rom: *const Rom,
//
//    ram: [0xffff]u8,
//    ram_ex: []u8,
//
//    bank: usize,
//    bank1: u8,
//    bank2: u8,
//    ram_bank: usize,
//    ram_enable: bool,
//    banking_mode: bool,
//
//    pub fn init(allocator: Allocator, rom: *const Rom) MBC1 {
//        const ram_ex = allocator.alloc(u8, rom.ram_size) catch |err| panic("MBC1.init: ram_ex alloc: {}", .{err});
//        return .{
//            .rom = rom,
//            .ram = std.mem.zeroes([0xffff]u8),
//            .ram_ex = ram_ex,
//            .bank = 0, 
//            .bank1 = 0, 
//            .bank2 = 0,
//            .ram_bank = 0,
//            .ram_enable = false, 
//            .banking_mode = false
//        };
//    }
//
//    pub fn readFn(self: *MBC1, addr: u16) u8 {
//        return switch (addr) {
//            0...0x3fff => self.rom.data[addr],
//            0x4000...0x7fff => self.rom.data[self.bank | (addr - 0x4000)],
//            0x8000...0x9fff => self.ram[addr],
//            0xa000...0xbfff => if (self.ram_enable) self.ram_ex[self.ram_bank | (addr - 0xa000)] else 0,
//            else => self.ram[addr],
//        };
//    }
//
//    pub fn writeFn(self: *MBC1, addr: u16, val: u8) void {
//        self.ram[addr] = val;
//        switch (addr) {
//            0x0...0x1fff => {
//                self.ram_enable = val & 0xf == 0xa;
//            },
//            0x2000...0x3fff => {
//                self.bank1 = if (val == 0) 1 else val & 0x1f;
//                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//            },
//            0x4000...0x5fff => {
//                self.bank2 = val & 0x3;
//                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//            },
//            0x6000...0x7fff => {
//                if (val != 0) {
//                    self.banking_mode = true;
//                    self.ram_bank = @intCast(usize, self.bank2) << 13;
//                } else {
//                    self.banking_mode = false;
//                    self.ram_bank = 0;
//                }
//            },
//            0xa000...0xbfff => {
//                if (self.ram_enable) {
//                    self.ram_ex[self.ram_bank | (addr - 0xa000)] = val;
//                }
//            },
//            else => {},
//        }
//    }
//};

pub const MBC = struct {
    readFn: fn (*MBC, u16) u8,
    writeFn: fn (*MBC, u16, u8) void,
    romBankFn: fn (*MBC) usize,
    getRAMFn: fn (*MBC) []u8,

    pub fn read(self: *MBC, addr: u16) u8 {
        return self.readFn(self, addr);
    }

    pub fn write(self: *MBC, addr: u16, val: u8) void {
        self.writeFn(self, addr, val);
    }

    pub fn readReg(self: *MBC, reg: Registers) u8 {
        return self.readFn(self, @enumToInt(reg));
    }

    pub fn writeReg(self: *MBC, reg: Registers, val: u8) void {
        self.writeFn(self, @enumToInt(reg), val);
    }

    pub fn romBank(self: *MBC) usize {
        return self.romBankFn(self);
    }

    pub fn getRAM(self: *MBC) []u8 {
        return self.getRAMFn(self);
    }
};

pub const MBC1 = struct {
    mbc: MBC,

    rom: *const ROM,

    ram: [0x10000]u8,
    ram_ex: []u8,

    bank: usize,
    bank1: u8,
    bank2: u8,
    ram_bank: usize,
    ram_enable: bool,
    banking_mode: bool,

    pub fn init(allocator: Allocator, rom: *const ROM) MBC1 {
        const ram_ex = allocator.alloc(u8, rom.ram_size)
            catch |err| panic("MBC1 ram_ex alloc: {}", .{err});
        return .{
            .mbc = MBC {.readFn = readFn, .writeFn = writeFn, .romBankFn = romBankFn, .getRAMFn = getRAMFn },
            .rom = rom,
            .ram = [1]u8{0} ** 0x10000,
            .ram_ex = ram_ex,
            .bank =  0x4000,
            .bank1 = 1,
            .bank2 = 0,
            .ram_bank = 0,
            .ram_enable = false,
            .banking_mode = false
        };
    }

    pub fn readFn(mbcI: *MBC, addr: u16) u8 {
        const self = @fieldParentPtr(MBC1, "mbc", mbcI);
        return switch (addr) {
           0x0000 ... 0x3fff => self.rom.data[addr],
           0x4000 ... 0x7fff => self.rom.data[self.bank | (addr - 0x4000)],
           0x8000 ... 0x9fff => self.ram[addr],
           0xa000 ... 0xbfff => if (self.ram_enable) self.ram_ex[self.ram_bank | (addr - 0xa000)] else 0,
           else => self.ram[addr]
        };
    }

    pub fn writeFn(mbcI: *MBC, addr: u16, val: u8) void {
        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
        switch (addr) {
            0x0000 ... 0x1fff => {
                self.ram_enable = val & 0xf == 0xa;
            },
            0x2000 ... 0x3fff => {
                self.bank1 = if (val == 0) 1 else val & 0x1f;
                //const b = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
                //self.bank = if (b == 0x8000 or b == 0x100000 or b == 0x180000) b + 0x4000 else b;
                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
            },
            0x4000 ... 0x5fff => {
                self.bank2 = val & 0x3;
                //const b = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
                //self.bank = if (b == 0x8000 or b == 0x100000 or b == 0x180000) b + 0x4000 else b;
                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
            },
            0x6000 ... 0x7fff => {
                if (val != 0) {
                    self.banking_mode = true;
                    self.ram_bank = @intCast(usize,self.bank2) << 13;
                }
                else {
                    self.banking_mode = false;
                    self.ram_bank = 0;
                }
            },
            0xa000 ... 0xbfff => {
                if (self.ram_enable) {
                    self.ram_ex[self.ram_bank | (addr - 0xa000)] = val;
                }
            },
            else => self.ram[addr] = val,
        }
    }

    pub fn romBankFn(mbcI: *MBC) usize {
        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
        return self.bank;
    }

    pub fn getRAMFn(mbcI: *MBC) []u8 {
        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
        return &self.ram;
    }

};
