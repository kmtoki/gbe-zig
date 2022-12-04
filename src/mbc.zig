const std = @import("std");
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const ROM = @import("rom.zig").ROM;
const MBCType = @import("rom.zig").MBCType;
const Registers = @import("utils.zig").Registers;

// MBC Interface implement by tagged union / switch inline else in zig version 0.10.0 later
pub const MBC = union(enum) {
    mbc1: *MBC1,

    // inline!!
    // require place to store MBCx struct data
    // but 'var mbc1' in MBC.init stack frame
    // because puts variable on caller level stack frame
    // TODO: into heap and unuse inline
    pub inline fn init(allocator: Allocator, rom: *const ROM) MBC {
        switch (rom.cartrige_type.mbc_type) {
            .mbc1 => {
                var mbc1 = MBC1.init(allocator, rom);
                return .{ .mbc1 = &mbc1 };
            },
            else => |t| panic("MBC.init: unimplement MBCType {any}", .{t}),
        }
    }

    pub fn deinit(self: MBC) void {
        switch (self) {
            inline else => |mbc| mbc.deinit(),
        }
    }

    pub fn read(self: MBC, addr: u16) u8 {
        return switch (self) {
            //.mbc1 => |mbc| mbc.read(addr),
            //else => |mbc| panic("MBC.read: unimplement {}", .{@tagName(mbc)}),
            inline else => |mbc| mbc.read(addr),
        };
    }

    pub fn readReg(self: MBC, reg: Registers) u8 {
        return self.read(@enumToInt(reg));
    }

    pub fn write(self: MBC, addr: u16, val: u8) void {
        switch (self) {
            inline else => |mbc| mbc.write(addr, val),
        }
    }

    pub fn writeReg(self: MBC, reg: Registers, val: u8) void {
        self.write(@enumToInt(reg), val);
    }

    pub fn getROMBank(self: MBC) usize {
        return switch (self) {
            inline else => |mbc| mbc.bank,
        };
    }

    pub fn getRam(self: MBC) []u8 {
        return switch (self) {
            inline else => |mbc| &mbc.ram,
        };
    }
};

pub const MBC1 = struct {
    allocator: Allocator,
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
        const ram_ex = allocator.alloc(u8, rom.ram_size) catch |err| {
            panic("MBC1.init alloc: {}", .{err});
        };
        return .{
            .allocator = allocator,
            .rom = rom,
            .ram = [1]u8{0} ** 0x10000,
            .ram_ex = ram_ex,
            .bank = 0, 
            .bank1 = 0, 
            .bank2 = 0,
            .ram_bank = 0,
            .ram_enable = false, 
            .banking_mode = false
        };
    }

    pub fn deinit(self: *MBC1) void {
        self.allocator.free(self.ram_ex);
    }

    fn read(self: *MBC1, addr: u16) u8 {
        return switch (addr) {
            0...0x3fff => self.rom.data[addr],
            0x4000...0x7fff => self.rom.data[self.bank | (addr - 0x4000)],
            0x8000...0x9fff => self.ram[addr],
            0xa000...0xbfff => if (self.ram_enable) self.ram_ex[self.ram_bank | (addr - 0xa000)] else 0,
            else => self.ram[addr],
        };
    }

    fn write(self: *MBC1, addr: u16, val: u8) void {
        switch (addr) {
            0x0000...0x1fff => {
                self.ram_enable = val & 0xf == 0xa;
            },
            0x2000...0x3fff => {
                self.bank1 = if (val == 0) 1 else val & 0x1f;
                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
            },
            0x4000...0x5fff => {
                self.bank2 = val & 0x3;
                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
            },
            0x6000...0x7fff => {
                if (val != 0) {
                    self.banking_mode = true;
                    self.ram_bank = @intCast(usize, self.bank2) << 13;
                } else {
                    self.banking_mode = false;
                    self.ram_bank = 0;
                }
            },
            0xa000...0xbfff => {
                if (self.ram_enable) {
                    self.ram_ex[self.ram_bank | (addr - 0xa000)] = val;
                }
            },
            0xff46 => {
                //DMA. todo: wait for 160 mcycle 
                const src = @intCast(u16,val) << 8;
                var i: u16 = 0;
                while (i < 0x100) : (i += 1) {
                    self.write(0xfe00 + i, self.read(src + i));
                }
                self.ram[addr] = val;
            },
            else => self.ram[addr] = val,
        }
    }
    fn bank(self: *MBC) usize {
        return self.bank;
    }

    fn ram(self: *MBC) []u8 {
        return &self.ram;
    }
};


// MBC Interface implement by @fieldParentPtr()
//pub const MBC = struct {
//    readFn: *const fn (*MBC, u16) u8,
//    writeFn: *const fn (*MBC, u16, u8) void,
//    getROMBankFn: *const fn (*MBC) usize,
//    getRAMFn: *const fn (*MBC) []u8,
//
//    pub fn read(self: *MBC, addr: u16) u8 {
//        return self.readFn(self, addr);
//    }
//
//    pub fn write(self: *MBC, addr: u16, val: u8) void {
//        self.writeFn(self, addr, val);
//    }
//
//    pub fn readReg(self: *MBC, reg: Registers) u8 {
//        return self.readFn(self, @enumToInt(reg));
//    }
//
//    pub fn writeReg(self: *MBC, reg: Registers, val: u8) void {
//        self.writeFn(self, @enumToInt(reg), val);
//    }
//
//    pub fn getROMBank(self: *MBC) usize {
//        return self.getROMBankFn(self);
//    }
//
//    pub fn getRAM(self: *MBC) []u8 {
//        return self.getRAMFn(self);
//    }
//};
//
//pub const MBC1 = struct {
//    mbc: MBC,
//    
//    allocator: Allocator,
//    rom: *const ROM,
//    ram: [0x10000]u8,
//    ram_ex: []u8,
//    bank: usize,
//    bank1: u8,
//    bank2: u8,
//    ram_bank: usize,
//    ram_enable: bool,
//    banking_mode: bool,
//
//    pub fn init(allocator: Allocator, rom: *const ROM) MBC1 {
//        const ram_ex = allocator.alloc(u8, rom.ram_size)
//            catch |err| panic("MBC1 ram_ex alloc: {}", .{err});
//        return .{
//            .mbc = MBC {.readFn = readFn, .writeFn = writeFn, .getROMBankFn = getROMBankFn, .getRAMFn = getRAMFn },
//            .allocator = allocator,
//            .rom = rom,
//            .ram = [1]u8{0} ** 0x10000,
//            .ram_ex = ram_ex,
//            .bank =  0x4000,
//            .bank1 = 1,
//            .bank2 = 0,
//            .ram_bank = 0,
//            .ram_enable = false,
//            .banking_mode = false
//        };
//    }
//
//    pub fn deinit(mbcI: *MBC) void {
//        const self = @fieldParentPtr(MBC1, "mbc", mbcI);
//        self.allocator.free(self.ram_ex);
//    }
//
//    pub fn readFn(mbcI: *MBC, addr: u16) u8 {
//        const self = @fieldParentPtr(MBC1, "mbc", mbcI);
//        return switch (addr) {
//           0x0000 ... 0x3fff => self.rom.data[addr],
//           0x4000 ... 0x7fff => self.rom.data[self.bank | (addr - 0x4000)],
//           0x8000 ... 0x9fff => self.ram[addr],
//           0xa000 ... 0xbfff => if (self.ram_enable) self.ram_ex[self.ram_bank | (addr - 0xa000)] else 0,
//           else => self.ram[addr]
//        };
//    }
//
//    pub fn writeFn(mbcI: *MBC, addr: u16, val: u8) void {
//        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
//        switch (addr) {
//            0x0000 ... 0x1fff => {
//                self.ram_enable = val & 0xf == 0xa;
//            },
//            0x2000 ... 0x3fff => {
//                self.bank1 = if (val == 0) 1 else val & 0x1f;
//                //const b = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//                //self.bank = if (b == 0x8000 or b == 0x100000 or b == 0x180000) b + 0x4000 else b;
//                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//            },
//            0x4000 ... 0x5fff => {
//                self.bank2 = val & 0x3;
//                //const b = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//                //self.bank = if (b == 0x8000 or b == 0x100000 or b == 0x180000) b + 0x4000 else b;
//                self.bank = @intCast(usize, self.bank2) << 19 | @intCast(usize, self.bank1) << 14;
//            },
//            0x6000 ... 0x7fff => {
//                if (val != 0) {
//                    self.banking_mode = true;
//                    self.ram_bank = @intCast(usize,self.bank2) << 13;
//                }
//                else {
//                    self.banking_mode = false;
//                    self.ram_bank = 0;
//                }
//            },
//            0xa000 ... 0xbfff => {
//                if (self.ram_enable) {
//                    self.ram_ex[self.ram_bank | (addr - 0xa000)] = val;
//                }
//            },
//            0xff46 => {
//                //DMA. todo: wait for 160 mcycle 
//                const src = @intCast(u16,val) << 8;
//                var i: u16 = 0;
//                while (i < 0x100) : (i += 1) {
//                    mbcI.write(0xfe00 + i, mbcI.read(src + i));
//                }
//                self.ram[addr] = val;
//            },
//            else => self.ram[addr] = val,
//        }
//    }
//
//    pub fn getROMBankFn(mbcI: *MBC) usize {
//        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
//        return self.bank;
//    }
//
//    pub fn getRAMFn(mbcI: *MBC) []u8 {
//        var self = @fieldParentPtr(MBC1, "mbc", mbcI);
//        return &self.ram;
//    }
//
//};
