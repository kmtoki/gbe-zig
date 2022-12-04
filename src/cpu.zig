const std = @import("std");
const panic = std.debug.panic;

const MBC = @import("mbc.zig").MBC;
const Logger = @import("logger.zig").Logger;

const utils = @import("utils.zig");
const toU16 = utils.toU16;
const sepU16 = utils.sepU16;
const bitSet = utils.bitSet;
const bitClear = utils.bitClear;
const bitCheck = utils.bitCheck;
const Registers = utils.Registers;

const Operand = enum { 
    A, F, B, C, D, E, H, L, 
    _A,
    AF, BC, DE, HL, SP,
    N, NN, 
    P_BC, P_DE, P_HL, P_SP, P_NN, P_FF00_N, P_FF00_C,
    P_HL_INC, P_HL_DEC,
    Zero, Carry, NotZero, NotCarry, Always,
    None,

    fn show(self: Operand) []const u8 {
        return switch (self) {
            .A => "A",
            .F => "F",
            .B => "B",
            .C => "C",
            .D => "D",
            .E => "E",
            .H => "H",
            .L => "L",
            .N => "N",
            ._A => "_A",
            .NN => "NN",
            .AF => "AF",
            .BC => "BC",
            .DE => "DE",
            .HL => "HL",
            .SP => "SP",
            .P_BC => "(BC)",
            .P_DE => "(DE)",
            .P_HL => "(HL)",
            .P_SP => "(SP)",
            .P_NN => "(NN)",
            .P_HL_INC => "(HL++)",
            .P_HL_DEC => "(HL--)",
            .P_FF00_N => "(FF00+N)",
            .P_FF00_C => "(FF00+C)",
            .Zero => "Z",
            .NotZero => "NZ",
            .Carry => "C",
            .NotCarry => "NC",
            .Always => "_",
            .None => "",
        };
    }
};

const u8OpResultWithCarryHalf = struct {
    result: u8, 
    carry: bool, 
    half: bool
};

const u16OpResultWithCarryHalf = struct {
    result: u16,
    carry: bool,
    half: bool
};

fn addU8WithCarryHalf(a: u8, b: u8) u8OpResultWithCarryHalf {
    var result: u8 = 0;
    const overflow = @addWithOverflow(u8, a, b, &result);
    return .{
        .result = result,
        .carry = overflow,
        .half = (a ^ b ^ result) & 0x10 != 0,
    };
}

fn addU16WithCarryHalf(a: u16, b: u16) u16OpResultWithCarryHalf {
    var result: u16 = 0;
    const overflow = @addWithOverflow(u16, a, b, &result);
    return .{
        .result = result,
        .carry = overflow,
        .half = (a ^ b ^ result) & 0x1000 != 0,
    };
}

fn subU8WithCarryHalf(a: u8, b: u8) u8OpResultWithCarryHalf {
    var result: u8 = 0;
    const overflow = @subWithOverflow(u8, a, b, &result);
    return .{
        .result = result,
        .carry = overflow,
        .half = (a ^ b ^ result) & 0x10 != 0,
    };
}

fn subU16WithCarryHalf(a: u16, b: u16) u16OpResultWithCarryHalf {
    var result: u16 = 0;
    const overflow = @subWithOverflow(u16, a, b, &result);
    return .{
        .result = result,
        .carry = overflow,
        .half = (a ^ b ^ result) & 0x1000 != 0,
    };
}

pub fn addU16ToSingedU8WithCarryHalf(a: u16, b: u8) u16OpResultWithCarryHalf {
    const n = @intCast(u16, bitClear(u8, b, 7));
    if (bitCheck(u8, b, 7)) {
        const i = 128 - n;
        const result = a -% i;
        return .{
            .result = result,
            .carry = (a ^ i ^ result) & 0x100 == 0,
            .half = (a ^ i ^ result) & 0x10 == 0,
        };
    } else {
        const result = a +% n;
        return .{
            .result = result,
            .carry = (a ^ n ^ result) & 0x100 != 0,
            .half = (a ^ n ^ result) & 0x10 != 0,
        };
    
    }
}

const LogInfoTag = enum {
    u8_hex,
    u16_hex,
    u8_signed,
    text,
    none,
};

const LogInfo = union(LogInfoTag) {
    u8_hex: u8,
    u16_hex: u16,
    u8_signed: u8,
    text: []const u8,
    none: void,
};

pub const CPU = struct {
    mbc: *MBC,
    logger: *Logger,

    a: u8,
    f: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,
    ime: bool,
    halting: bool,
    cycle: u8,
    serial_counter: u8,
    serial_buffer: [0xff]u8,
    serial_buffer_pos: usize,
    sys_counter: u16,
    exe_counter: usize,

    pub fn init(mbc: *MBC, logger: *Logger) CPU {
        return .{
            .mbc = mbc,
            .logger = logger,
            .a = 0,
            .f = 0,
            .b = 0,
            .c = 0,
            .d = 0,
            .e = 0,
            .h = 0,
            .l = 0,
            .sp = 0xfffe,
            .pc = 0x100,
            .ime = false,
            .halting = false,
            .cycle = 0,
            .serial_counter = 0,
            .serial_buffer = [1]u8{0} ** 0xff,
            .serial_buffer_pos = 0,
            .sys_counter = 0,
            .exe_counter = 1,
        };
    }

    fn getAF(self: *CPU) u16 { return toU16(self.a, self.f); }
    fn getBC(self: *CPU) u16 { return toU16(self.b, self.c); }
    fn getDE(self: *CPU) u16 { return toU16(self.d, self.e); }
    fn getHL(self: *CPU) u16 { return toU16(self.h, self.l); }

    fn setAF(self: *CPU, v: u16) void { const hl = sepU16(v); self.a = hl.h; self.f = hl.l & 0xf0; }
    fn setBC(self: *CPU, v: u16) void { const hl = sepU16(v); self.b = hl.h; self.c = hl.l; }
    fn setDE(self: *CPU, v: u16) void { const hl = sepU16(v); self.d = hl.h; self.e = hl.l; }
    fn setHL(self: *CPU, v: u16) void { const hl = sepU16(v); self.h = hl.h; self.l = hl.l; }

    fn getCarry(self: *CPU) bool    { return bitCheck(u8, self.f, 4); }
    fn getHalf(self: *CPU) bool     { return bitCheck(u8, self.f, 5); }
    fn getNegative(self: *CPU) bool { return bitCheck(u8, self.f, 6); }
    fn getZero(self: *CPU) bool     { return bitCheck(u8, self.f, 7); }

    fn setCarry(self: *CPU, b: bool) void    { self.f = if (b) bitSet(u8,self.f,4) else bitClear(u8,self.f,4); }
    fn setHalf(self: *CPU, b: bool) void     { self.f = if (b) bitSet(u8,self.f,5) else bitClear(u8,self.f,5); }
    fn setNegative(self: *CPU, b: bool) void { self.f = if (b) bitSet(u8,self.f,6) else bitClear(u8,self.f,6); }
    fn setZero(self: *CPU, b: bool) void     { self.f = if (b) bitSet(u8,self.f,7) else bitClear(u8,self.f,7); }



    pub fn log(self: *CPU, instr: []const u8, op1: Operand, op2: Operand, info: LogInfo) void {
        if (self.logger.is_print or self.logger.is_dump) {
            const stateFmt = "--- {d}\nbank:{x}\npc:{x:0>4} {s}\nsp:{x:0>4} {s}\nf:{s} a:{x:0>2} bc:{x:0>4} de:{x:0>4} hl:{x:0>4} ime:{d} IF:{b:0>5} IE:{b:0>5} HALT:{d}\n";

            var rom = [1]u8{0} ** 50;
            var pc = self.pc -% 5;
            var n: usize = 0;
            while (n <= 36) : (n += 3) {
                if ((self.pc -% 1) == pc) {
                    _ = std.fmt.bufPrint(rom[n..n+5], "|{x:0>2}| ", .{self.read(pc)}) catch {};
                    n += 2;
                } else {
                    _ = std.fmt.bufPrint(rom[n..n+3], "{x:0>2} ", .{self.read(pc)}) catch {};
                }
                pc +%= 1;
            }

            var stack = [1]u8{0} ** 50;
            var sp = self.sp +% 4;
            var i: usize = 0;
            while (i <= 36) : (i += 3) {
                if (self.sp == sp) {
                    _ = std.fmt.bufPrint(stack[i..i+5], "|{x:0>2}| ", .{self.read(sp)}) catch {};
                    i += 2;
                } else {
                    _ = std.fmt.bufPrint(stack[i..i+3], "{x:0>2} ", .{self.read(sp)}) catch {};
                }
                sp -%= 1;
            }

            var stateBuf = [1]u8{0} ** 200;
            const flags: [4]u8 = .{
                if (self.getZero()) 'Z' else '_',
                if (self.getNegative()) 'N' else '_',
                if (self.getHalf()) 'H' else '_',
                if (self.getCarry()) 'C' else '_'
            };
            _ = std.fmt.bufPrint(
                &stateBuf, stateFmt, .{
                    self.exe_counter, 
                    self.mbc.getROMBank(),
                    self.pc -% 1, 
                    rom[0..n],
                    self.sp,
                    stack[0..i],
                    flags, 
                    self.a, 
                    toU16(self.b, self.c),
                    toU16(self.d, self.e), 
                    toU16(self.h, self.l), 
                    @boolToInt(self.ime),
                    self.readReg(.IF),
                    self.readReg(.IE),
                    @boolToInt(self.halting),
                }
            ) catch {};
            var instrBuf = [1]u8{0} ** 45;
            _ = std.fmt.bufPrint(&instrBuf, "> {s} {s} {s} ", 
                .{instr, op1.show(), op2.show()}
            ) catch {};

            var infoBuf = [1]u8{0} ** 10;
            switch (info) {
                .u8_hex => |h| _ = std.fmt.bufPrint(&infoBuf, "{x:0>2}", .{h}) catch {},
                .u16_hex => |h| _ = std.fmt.bufPrint(&infoBuf, "{x:0>4}", .{h}) catch {},
                .u8_signed => |h| {
                    var s: u8 = ' ';
                    var int: u8 = bitClear(u8, h, 7);
                    if (bitCheck(u8, h, 7)) {
                        s = '-';
                        int = 128 - int;
                    } else {
                        s = '+';
                    }
                    _ = std.fmt.bufPrint(&infoBuf, "{c}{x:0>2}", .{s, int}) catch {};
                },
                .text => |t| _ = std.fmt.bufPrint(&infoBuf, "{s}", .{t}) catch {},
                .none => {}
            }

            var buf = [1]u8{0} ** 0xff;
            var j: usize = 0;
            for (stateBuf) |b| {
                if (b == 0) break;
                buf[j] = b;
                j += 1;
            }
            for (instrBuf) |b| {
                if (b == 0) break;
                buf[j] = b;
                j += 1;
            }
            for (infoBuf) |b| {
                if (b == 0) break;
                buf[j] = b;
                j += 1;
            }
            buf[j] = '\n';

            self.logger.log(&buf);
        }
    }

    pub fn tick(self: *CPU) void {
        self.cycle +%= 1;
    }

    pub fn step(self: *CPU) void {
        self.cycle = 0;

        if (self.halting) {
            self.tick();
        } else {
            self.dispatch();
        }

        var i: usize = 0;
        while (i < self.cycle * 4) :  (i += 1) {
            self.serial();
            self.timer();
            self.interrupt();
            self.sys_counter +%= 1;
        }

        self.exe_counter +%= 1;
    }

    fn serial(self: *CPU) void {
        const sc = self.readReg(.SC);
        if (bitCheck(u8, sc, 7)) {
            const clockList = [4]usize{512, 256, 16, 8};
            const clock = clockList[sc & 0b11];
            if (self.sys_counter % clock == 0) {
                const sb = self.readReg(.SB);

                self.serial_buffer[self.serial_buffer_pos] = sb;
                if (self.serial_buffer_pos < (self.serial_buffer.len - 1)) {
                    self.serial_buffer_pos +%= 1;
                } else {
                    self.serial_buffer_pos = 0;
                }
                self.logger.logFmt("Serial: read '{x:0>2}'", .{sb});

                self.writeReg(.SC, bitClear(u8, sc, 7));
                self.writeReg(.IF, bitSet(u8, self.readReg(.IF), 3));
            }
        }
    }

    fn timer(self: *CPU) void {
        if (self.sys_counter % 256 == 0) {
            self.writeReg(.DIV, self.readReg(.DIV) +% 1);
        }

        const tac = self.readReg(.TAC);
        if (bitCheck(u8, tac, 2)) {
            const clockList = [4]u16{1024, 16, 64, 256};
            const clock = clockList[tac & 0b11];
            if (self.sys_counter % clock == 0) {
                const tima = addU8WithCarryHalf(self.readReg(.TIMA), 1);
                if (tima.carry) {
                    self.writeReg(.IF, bitSet(u8, self.readReg(.IF), 2));
                    self.writeReg(.TIMA, self.readReg(.TMA));
                } else {
                    self.writeReg(.TIMA, tima.result);
                }
            }
        }
    }

    fn interrupt(self: *CPU) void {
        if (self.readReg(.IE) & self.readReg(.IF) != 0) {
            self.halting = false;
        }

        if (self.ime) {
            self.halting = false;

            const enable = self.readReg(.IE);
            const request = self.readReg(.IF);
            var addr: u16 = 0;
            var n: u8 = 0;
            var name: []const u8 = undefined;
            if (bitCheck(u8, enable, 0) and bitCheck(u8, request, 0)) {
                addr = 0x40;
                n = 0;
                name = "VBlack";
            } else if (bitCheck(u8, enable, 1) and bitCheck(u8, request, 1)) {
                addr = 0x48;
                n = 1;
                name = "LSTAT";
            } else if (bitCheck(u8, enable, 2) and bitCheck(u8, request, 2)) {
                addr = 0x50;
                n = 2;
                name = "Timer";
            } else if (bitCheck(u8, enable, 3) and bitCheck(u8, request, 3)) {
                addr = 0x58;
                n = 3;
                name = "Serial";
            } else if (bitCheck(u8, enable, 4) and bitCheck(u8, request, 4)) {
                addr = 0x60;
                n = 4;
                name = "Joypad";
            }

            if (addr != 0) {
                std.debug.print("Interrupt: {s} {x}\n", .{name, addr});

                self.push16(self.pc);
                self.pc = addr;
                self.ime = false;
                self.halting = false;
                self.writeReg(.IF, bitClear(u8, self.readReg(.IF), n));
                self.logger.logFmt("Interrupt: {s}", .{name});

                self.tick();
                self.tick();
                self.tick();
            }
        }
    }

    fn read(self: *CPU, addr: u16) u8 {
        defer self.tick();
        return self.mbc.read(addr);
    }

    fn write(self: *CPU, addr: u16, v: u8) void {
        self.mbc.write(addr, v);
        self.tick();
    }

    fn readReg(self: *CPU, reg: Registers) u8 {
        return self.mbc.readReg(reg);
    }

    fn writeReg(self: *CPU, reg: Registers, v: u8) void {
        self.mbc.writeReg(reg, v);
    }

    fn fetch8(self: *CPU) u8 {
        defer {
            self.pc +%= 1;
            self.tick();
        }
        return self.read(self.pc);
    }

    fn fetch16(self: *CPU) u16 {
        const l = self.fetch8();
        const h = self.fetch8();
        return toU16(h, l);
    }

    fn load8(self: *CPU, op: Operand) u8 {
        return switch (op) {
            .A => self.a,
            ._A => self.a,
            .F => self.f,
            .B => self.b,
            .C => self.c,
            .D => self.d,
            .E => self.e,
            .H => self.h,
            .L => self.l,
            .N => self.fetch8(),
            .P_BC => self.read(toU16(self.b, self.c)),
            .P_DE => self.read(toU16(self.d, self.e)),
            .P_HL => self.read(toU16(self.h, self.l)),
            .P_NN => self.read(self.fetch16()),
            .P_HL_INC => {
                const hl = self.getHL();
                self.setHL(hl +% 1);
                return self.read(hl);
            },
            .P_HL_DEC => {
                const hl = self.getHL();
                self.setHL(hl -% 1);
                return self.read(hl);
            },
            .P_FF00_C => self.read(0xff00 + @intCast(u16, self.c)),
            .P_FF00_N => self.read(0xff00 + @intCast(u16, self.fetch8())),
            else => panic("CPU.load8: unexpected Operand", .{}),
        };
    }

    fn load16(self: *CPU, op: Operand) u16 {
        return switch (op) {
            .AF => toU16(self.a, self.f),
            .BC => toU16(self.b, self.c),
            .DE => toU16(self.d, self.e),
            .HL => toU16(self.h, self.l),
            .SP => self.sp,
            .NN => self.fetch16(),
            else => panic("CPU.load16: unexpected Operand", .{}),
        };
    }

    fn store8(self: *CPU, op: Operand, v: u8) void {
        switch (op) {
            .A => self.a = v,
            ._A => self.a = v,
            .F => self.f = v & 0xf0,
            .B => self.b = v,
            .C => self.c = v,
            .D => self.d = v,
            .E => self.e = v,
            .H => self.h = v,
            .L => self.l = v,
            .P_BC => self.write(toU16(self.b, self.c), v),
            .P_DE => self.write(toU16(self.d, self.e), v),
            .P_HL => self.write(toU16(self.h, self.l), v),
            .P_NN => self.write(self.fetch16(), v),
            .P_HL_INC => {
                const hl = self.getHL();
                self.setHL(hl +% 1);
                self.write(hl, v);
            },
            .P_HL_DEC => {
                const hl = self.getHL();
                self.setHL(hl -% 1);
                self.write(hl, v);
            },
            .P_FF00_C => self.write(0xff00 + @intCast(u16, self.c), v),
            .P_FF00_N => self.write(0xff00 + @intCast(u16, self.fetch8()), v),
            else => panic("CPU.store8: unexpected Operand", .{}),
        }
    }

    fn store16(self: *CPU, op: Operand, v: u16) void {
        switch (op) {
            .AF => self.setAF(v),
            .BC => self.setBC(v),
            .DE => self.setDE(v),
            .HL => self.setHL(v),
            .P_NN => {
                const hl = sepU16(v);
                const addr = self.fetch16();
                self.write(addr, hl.l);
                self.write(addr + 1, hl.h);
                //self.cycle -= 1;
            },
            .SP => self.sp = v,
            else => panic("CPU.store16: unexpected Operand", .{}),
        }
    }

    fn push8(self: *CPU, v: u8) void {
        self.sp -%= 1;
        self.write(self.sp, v);
    }

    fn pop8(self: *CPU) u8 {
        defer self.sp +%= 1;
        return self.read(self.sp);
    }

    fn push16(self: *CPU, v: u16) void {
        const hl = sepU16(v);
        self.push8(hl.h);
        self.push8(hl.l);
    }

    fn pop16(self: *CPU) u16 {
        const l = self.pop8();
        const h = self.pop8();
        return toU16(h, l);
    }

    fn cond(self: *CPU, op: Operand) bool {
        return switch (op) {
            .NotZero => !self.getZero(),
            .Zero => self.getZero(),
            .NotCarry => !self.getCarry(),
            .Carry => self.getCarry(),
            .Always => true,
            else => panic("CPU.cond: unexpected Operand {}", .{op}),
        };
    }

    fn ld8(self: *CPU, op1: Operand, op2: Operand) void {
        self.log("LD", op1, op2, .none);
        self.store8(op1, self.load8(op2));
    }

    fn ld16(self: *CPU, op1: Operand, op2: Operand) void {
        self.log("LD", op1, op2, .none);
        self.store16(op1, self.load16(op2));
    }

    fn ld16_hl_sp_n(self: *CPU) void {
        const n = self.fetch8();

        self.pc -%=1;
        self.log("LD", .HL, .SP, .{.u8_signed = n});
        self.pc +%=1;
        
        const a = addU16ToSingedU8WithCarryHalf(self.sp, n);
        self.setHL(a.result);
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(false);
        self.setZero(false);
        self.tick();
    }

    fn push(self: *CPU, op: Operand) void {
        self.log("PUSH", op, .None, .none);
        const v = self.load16(op);
        self.tick();
        self.push16(v);
    }

    fn pop(self: *CPU, op: Operand) void {
        self.log("POP", op, .None, .none);
        self.store16(op, self.pop16());
    }

    fn add(self: *CPU, op: Operand) void {
        self.log("ADD", op, .None, .none);
        const a = addU8WithCarryHalf(self.a, self.load8(op));
        self.a = a.result;
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(false);
        self.setZero(self.a == 0);
    }

    fn adc(self: *CPU, op: Operand) void {
        self.log("ADC", op, .None, .none);
        const a = addU8WithCarryHalf(self.a, self.load8(op));
        const b = addU8WithCarryHalf(a.result, @boolToInt(self.getCarry()));
        self.a = b.result;
        self.setCarry(a.carry or b.carry);
        self.setHalf(a.half or b.half);
        self.setNegative(false);
        self.setZero(self.a == 0);
    }

    fn sub(self: *CPU, op: Operand) void {
        self.log("SUB", op, .None, .none);
        const a = subU8WithCarryHalf(self.a, self.load8(op));
        self.a = a.result;
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(true);
        self.setZero(self.a == 0);
    }

    fn sbc(self: *CPU, op: Operand) void {
        self.log("SBC", op, .None, .none);
        const a = subU8WithCarryHalf(self.a, self.load8(op));
        const b = subU8WithCarryHalf(a.result, @boolToInt(self.getCarry()));
        self.a = b.result;
        self.setCarry(a.carry or b.carry);
        self.setHalf(a.half or b.half);
        self.setNegative(true);
        self.setZero(self.a == 0);
    }

    fn and_(self: *CPU, op: Operand) void {
        self.log("AND", op, .None, .none);
        self.a = self.a & self.load8(op);
        self.setCarry(false);
        self.setHalf(true);
        self.setNegative(false);
        self.setZero(self.a == 0);
    }

    fn or_(self: *CPU, op: Operand) void {
        self.log("OR", op, .None, .none);
        self.a = self.a | self.load8(op);
        self.setCarry(false);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(self.a == 0);
    }

    fn xor(self: *CPU, op: Operand) void {
        self.log("XOR", op, .None, .none);
        self.a = self.a ^ self.load8(op);
        self.setCarry(false);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(self.a == 0);
    }

    fn cp(self: *CPU, op: Operand) void {
        self.log("CP", op, .None, .none);
        const a = subU8WithCarryHalf(self.a, self.load8(op));
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(true);
        self.setZero(a.result == 0);
    }

    fn inc8(self: *CPU, op: Operand) void {
        self.log("INC", op, .None, .none);
        const a = addU8WithCarryHalf(self.load8(op), 1);
        self.store8(op, a.result);
        self.setHalf(a.half);
        self.setNegative(false);
        self.setZero(a.result == 0);
    }

    fn dec8(self: *CPU, op: Operand) void {
        self.log("DEC", op, .None, .none);
        const a = subU8WithCarryHalf(self.load8(op), 1);
        self.store8(op, a.result);
        self.setHalf(a.half);
        self.setNegative(true);
        self.setZero(a.result == 0);
    }

    fn add_hl(self: *CPU, op: Operand) void {
        self.log("ADD", .HL, op, .none);
        const a = addU16WithCarryHalf(self.getHL(), self.load16(op));
        self.setHL(a.result);
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(false);
    }

    fn add_sp_n(self: *CPU) void {
        const n = self.fetch8();

        self.pc -%= 1;
        self.log("ADD", .SP, .N, .{.u8_signed = n});
        self.pc +%= 1;

        const a = addU16ToSingedU8WithCarryHalf(self.sp, n);

        //std.debug.print("ADD SP:{x:0>4} N:{d:0>4} -> SP:{x:0>4} C:{d} H:{d}\n", .{self.sp, n, a.result, @boolToInt(a.carry), @boolToInt(a.half)});

        self.sp = a.result;
        self.setCarry(a.carry);
        self.setHalf(a.half);
        self.setNegative(false);
        self.setZero(false);
        self.tick();
        self.tick();
    }

    fn inc16(self: *CPU, op: Operand) void {
        self.log("INC", op, .None, .none);
        const a = addU16WithCarryHalf(self.load16(op), 1);
        self.store16(op, a.result);
    }

    fn dec16(self: *CPU, op: Operand) void {
        self.log("DEC", op, .None, .none);
        const a = subU16WithCarryHalf(self.load16(op), 1);
        self.store16(op, a.result);
    }
 
    fn daa(self: *CPU) void {
        self.log("DAA", .None, .None, .none);
        var adjust: u8 = 0;
        adjust |= if (self.getCarry()) @as(u8, 0x60) else 0;
        adjust |= if (self.getHalf())  @as(u8, 0x06) else 0;
        if (!self.getNegative()) {
            adjust |= if (self.a & 0x0f > 0x09) @as(u8,0x06) else 0;
            adjust |= if (self.a > 0x99) @as(u8,0x60) else 0;
            self.a +%= adjust;
        } else {
            self.a -%= adjust;
        }
        self.setCarry(adjust >= 0x60);
        self.setHalf(false);
        self.setZero(self.a == 0);
    }
    
    //fn daa(self: *CPU) void {
    //    self.log("DAA", .None, .None, .none);

    //    var a: i16 = self.a;
    //    if (!self.getNegative()) {
    //        if (self.getCarry() or self.a > 0x99) {
    //            a += 0x60;
    //            self.setCarry(true);
    //        }
    //        if (self.getHalf() or self.a > 0x9) {
    //            a += 0x6;
    //        }
    //    } else {
    //        if (self.getCarry()) {
    //            a -= 0x60;
    //        }
    //        if (self.getHalf()) {
    //            a -= 0x6;
    //        }
    //    }

    //    self.a = @intCast(u8, a & 0xff);

    //    self.setHalf(false);
    //    self.setZero(self.a == 0);
    //}



    fn cpl(self: *CPU) void {
        self.log("CPL", .None, .None, .none);
        self.a ^= 0xff;
        self.setHalf(true);
        self.setNegative(true);
    }

    fn ccf(self: *CPU) void {
        self.log("CCF", .None, .None, .none);
        self.setCarry(!self.getCarry());
        self.setHalf(false);
        self.setNegative(false);
    }

    fn scf(self: *CPU) void {
        self.log("SCF", .None, .None, .none);
        self.setCarry(true);
        self.setHalf(false);
        self.setNegative(false);
    }

    fn di(self: *CPU) void {
        self.log("DI", .None, .None, .none);
        self.ime = false;
    }

    fn ei(self: *CPU) void {
        self.log("EI", .None, .None, .none);
        self.ime = true;
    }

    fn halt(self: *CPU) void {
        self.log("HALT", .None, .None, .none);
        self.halting = true;
    }

    fn stop(self: *CPU) void {
        self.log("STOP", .None, .None, .none);
        //self.halting = true;
    }

    fn nop(self: *CPU) void {
        self.log("NOP", .None, .None, .none);
    }

    fn jp(self: *CPU, op: Operand) void {
        const nn = self.fetch16();

        self.pc -%= 2;
        self.log("JP", op, .None, .{.u16_hex = nn});
        self.pc +%= 2;

        if (self.cond(op)) {
            self.pc = nn;
            self.tick();
        }
    }

    fn jp_p_hl(self: *CPU) void {
        const hl = self.getHL();
        self.log("JP", .HL, .None, .{.u16_hex = hl});
        self.pc = hl;
        self.tick();
    }

    fn jr(self: *CPU, op: Operand) void {
        const n = self.fetch8();

        self.pc -%= 1;
        self.log("JR", op, .None, .{.u8_signed = n});
        self.pc +%= 1;

        if (self.cond(op)) {
            self.pc = addU16ToSingedU8WithCarryHalf(self.pc, n).result;
            self.tick();
        }
    }

    fn call(self: *CPU, op: Operand) void {
        const nn = self.fetch16();

        self.pc -%= 2;
        self.log("CALL", op, .None, .{.u16_hex = nn});
        self.pc +%= 2;

        if (self.cond(op)) {
            self.tick();
            self.push16(self.pc);
            self.pc = nn;
        }
    }

    fn ret(self: *CPU, op: Operand) void {
        self.log("RET", op, .None, .none);
        if (self.cond(op)) {
            self.pc = self.pop16();
            self.tick();
        }
    }

    fn reti(self: *CPU) void {
        const pc = self.pop16();

        self.sp -%= 2;
        self.log("RETI", .None, .None, .{.u16_hex = self.pc});
        self.sp +%= 2;

        self.pc = pc;
        self.tick();
        self.ime = true;
    }

    fn rst(self: *CPU, addr: u16) void {
        self.log("RST", .None, .None, .{.u16_hex = addr});
        self.tick();
        self.push16(self.pc);
        self.pc = addr;
    }


    fn swap(self: *CPU, op: Operand) void {
        self.log("SWAP", op, .None, .none);
        const r = self.load8(op); 
        const a = (r << 4) | (r >> 4);
        self.store8(op, a);
        self.setCarry(false);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(a == 0);
    }

    fn rlc(self: *CPU, op: Operand) void {
        self.log("RLC", op, .None, .none);
        const r = self.load8(op);
        const c = r >> 7;
        const a = (r << 1) | c;
        self.store8(op, a);
        self.setCarry(c == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(if (op == ._A) false else a == 0);
    }
 
    fn rl(self: *CPU, op: Operand) void {
        self.log("RL", op, .None, .none);
        const r = self.load8(op);
        const a = (r << 1) | @boolToInt(self.getCarry());
        self.store8(op, a);
        self.setCarry(r >> 7 == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(if (op == ._A) false else a == 0);
    }
 
    fn rrc(self: *CPU, op: Operand) void {
        self.log("RRC", op, .None, .none);
        const r = self.load8(op);
        const c = r & 1;
        const a = (c << 7) | (r >> 1);
        self.store8(op, a);
        self.setCarry(c == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(if (op == ._A) false else a == 0);
    }
 
    fn rr(self: *CPU, op: Operand) void {
        self.log("RR", op, .None, .none);
        const r = self.load8(op);
        const a = (@as(u8, @boolToInt(self.getCarry())) << 7) | (r >> 1);
        self.store8(op, a);
        self.setCarry(r & 1 == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(if (op == ._A) false else a == 0);
    }
 
    fn sla(self: *CPU, op: Operand) void {
        self.log("SLA", op, .None, .none);
        const r = self.load8(op);
        const a = r << 1;
        self.store8(op, a);
        self.setCarry(r >> 7 == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(a == 0);
    }

    fn sra(self: *CPU, op: Operand) void {
        self.log("SRA", op, .None, .none);
        const r = self.load8(op);
        const a = (r & 0b10000000) | (r >> 1);
        self.store8(op, a);
        self.setCarry(r & 1 == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(a == 0);
    }

    fn srl(self: *CPU, op: Operand) void {
        self.log("SRL", op, .None, .none);
        const r = self.load8(op);
        const a = r >> 1;
        self.store8(op, a);
        self.setCarry(r & 1 == 1);
        self.setHalf(false);
        self.setNegative(false);
        self.setZero(a == 0);
    }

    fn bit(self: *CPU, n: u8, op: Operand) void {
        self.log("BIT", op, .None, .{.u8_hex = n});
        const a = bitCheck(u8, self.load8(op), n);
        self.setHalf(true);
        self.setNegative(false);
        self.setZero(a == false);
    }

    fn set(self: *CPU, n: u8, op: Operand) void {
        self.log("SET", op, .None, .{.u8_hex = n});
        self.store8(op, bitSet(u8, self.load8(op), n));
    }

    fn res(self: *CPU, n: u8, op: Operand) void {
        self.log("RES", op, .None, .{.u8_hex = n});
        self.store8(op, bitClear(u8, self.load8(op), n));
    }


    fn dispatch(self: *CPU) void {
        const instruction = self.fetch8();
        switch (instruction) {
            0x3e => self.ld8(.A, .N),
            0x06 => self.ld8(.B, .N),
            0x0e => self.ld8(.C, .N),
            0x16 => self.ld8(.D, .N),
            0x1e => self.ld8(.E, .N),
            0x26 => self.ld8(.H, .N),
            0x2e => self.ld8(.L, .N),
            0x7f => self.ld8(.A, .A),
            0x78 => self.ld8(.A, .B),
            0x79 => self.ld8(.A, .C),
            0x7a => self.ld8(.A, .D),
            0x7b => self.ld8(.A, .E),
            0x7c => self.ld8(.A, .H),
            0x7d => self.ld8(.A, .L),
            0x7e => self.ld8(.A, .P_HL),
            0x0a => self.ld8(.A, .P_BC),
            0x1a => self.ld8(.A, .P_DE),
            0x47 => self.ld8(.B, .A),
            0x40 => self.ld8(.B, .B),
            0x41 => self.ld8(.B, .C),
            0x42 => self.ld8(.B, .D),
            0x43 => self.ld8(.B, .E),
            0x44 => self.ld8(.B, .H),
            0x45 => self.ld8(.B, .L),
            0x46 => self.ld8(.B, .P_HL),
            0x4f => self.ld8(.C, .A),
            0x48 => self.ld8(.C, .B),
            0x49 => self.ld8(.C, .C),
            0x4a => self.ld8(.C, .D),
            0x4b => self.ld8(.C, .E),
            0x4c => self.ld8(.C, .H),
            0x4d => self.ld8(.C, .L),
            0x4e => self.ld8(.C, .P_HL),
            0x57 => self.ld8(.D, .A),
            0x50 => self.ld8(.D, .B),
            0x51 => self.ld8(.D, .C),
            0x52 => self.ld8(.D, .D),
            0x53 => self.ld8(.D, .E),
            0x54 => self.ld8(.D, .H),
            0x55 => self.ld8(.D, .L),
            0x56 => self.ld8(.D, .P_HL),
            0x5f => self.ld8(.E, .A),
            0x58 => self.ld8(.E, .B),
            0x59 => self.ld8(.E, .C),
            0x5a => self.ld8(.E, .D),
            0x5b => self.ld8(.E, .E),
            0x5c => self.ld8(.E, .H),
            0x5d => self.ld8(.E, .L),
            0x5e => self.ld8(.E, .P_HL),
            0x67 => self.ld8(.H, .A),
            0x60 => self.ld8(.H, .B),
            0x61 => self.ld8(.H, .C),
            0x62 => self.ld8(.H, .D),
            0x63 => self.ld8(.H, .E),
            0x64 => self.ld8(.H, .H),
            0x65 => self.ld8(.H, .L),
            0x66 => self.ld8(.H, .P_HL),
            0x6f => self.ld8(.L, .A),
            0x68 => self.ld8(.L, .B),
            0x69 => self.ld8(.L, .C),
            0x6a => self.ld8(.L, .D),
            0x6b => self.ld8(.L, .E),
            0x6c => self.ld8(.L, .H),
            0x6d => self.ld8(.L, .L),
            0x6e => self.ld8(.L, .P_HL),

            0x70 => self.ld8(.P_HL, .B),
            0x71 => self.ld8(.P_HL, .C),
            0x72 => self.ld8(.P_HL, .D),
            0x73 => self.ld8(.P_HL, .E),
            0x74 => self.ld8(.P_HL, .H),
            0x75 => self.ld8(.P_HL, .L),
            0x36 => self.ld8(.P_HL, .N),
            0x02 => self.ld8(.P_BC, .A),
            0x12 => self.ld8(.P_DE, .A),
            0x77 => self.ld8(.P_HL, .A),
            0xea => self.ld8(.P_NN, .A),

            0xf0 => self.ld8(.A, .P_FF00_N),
            0xf2 => self.ld8(.A, .P_FF00_C),
            0xfa => self.ld8(.A, .P_NN),
            0xe0 => self.ld8(.P_FF00_N, .A),
            0xe2 => self.ld8(.P_FF00_C, .A),

            0x22 => self.ld8(.P_HL_INC, .A),
            0x2a => self.ld8(.A, .P_HL_INC),
            0x32 => self.ld8(.P_HL_DEC, .A),
            0x3a => self.ld8(.A, .P_HL_DEC),

            0x01 => self.ld16(.BC, .NN),
            0x11 => self.ld16(.DE, .NN),
            0x21 => self.ld16(.HL, .NN),
            0x31 => self.ld16(.SP, .NN),
            0xf9 => self.ld16(.SP, .HL),
            0x08 => self.ld16(.P_NN, .SP),
            0xf8 => self.ld16_hl_sp_n(),

            0xf5 => self.push(.AF),
            0xc5 => self.push(.BC),
            0xd5 => self.push(.DE),
            0xe5 => self.push(.HL),
            0xf1 => self.pop(.AF),
            0xc1 => self.pop(.BC),
            0xd1 => self.pop(.DE),
            0xe1 => self.pop(.HL),

            0x87 => self.add(.A),
            0x80 => self.add(.B),
            0x81 => self.add(.C),
            0x82 => self.add(.D),
            0x83 => self.add(.E),
            0x84 => self.add(.H),
            0x85 => self.add(.L),
            0x86 => self.add(.P_HL),
            0xc6 => self.add(.N),

            0x8f => self.adc(.A),
            0x88 => self.adc(.B),
            0x89 => self.adc(.C),
            0x8a => self.adc(.D),
            0x8b => self.adc(.E),
            0x8c => self.adc(.H),
            0x8d => self.adc(.L),
            0x8e => self.adc(.P_HL),
            0xce => self.adc(.N),

            0x97 => self.sub(.A),
            0x90 => self.sub(.B),
            0x91 => self.sub(.C),
            0x92 => self.sub(.D),
            0x93 => self.sub(.E),
            0x94 => self.sub(.H),
            0x95 => self.sub(.L),
            0x96 => self.sub(.P_HL),
            0xd6 => self.sub(.N),

            0x9f => self.sbc(.A),
            0x98 => self.sbc(.B),
            0x99 => self.sbc(.C),
            0x9a => self.sbc(.D),
            0x9b => self.sbc(.E),
            0x9c => self.sbc(.H),
            0x9d => self.sbc(.L),
            0x9e => self.sbc(.P_HL),
            0xde => self.sbc(.N),

            0xa7 => self.and_(.A),
            0xa0 => self.and_(.B),
            0xa1 => self.and_(.C),
            0xa2 => self.and_(.D),
            0xa3 => self.and_(.E),
            0xa4 => self.and_(.H),
            0xa5 => self.and_(.L),
            0xa6 => self.and_(.P_HL),
            0xe6 => self.and_(.N),

            0xb7 => self.or_(.A),
            0xb0 => self.or_(.B),
            0xb1 => self.or_(.C),
            0xb2 => self.or_(.D),
            0xb3 => self.or_(.E),
            0xb4 => self.or_(.H),
            0xb5 => self.or_(.L),
            0xb6 => self.or_(.P_HL),
            0xf6 => self.or_(.N),

            0xaf => self.xor(.A),
            0xa8 => self.xor(.B),
            0xa9 => self.xor(.C),
            0xaa => self.xor(.D),
            0xab => self.xor(.E),
            0xac => self.xor(.H),
            0xad => self.xor(.L),
            0xae => self.xor(.P_HL),
            0xee => self.xor(.N),

            0xbf => self.cp(.A),
            0xb8 => self.cp(.B),
            0xb9 => self.cp(.C),
            0xba => self.cp(.D),
            0xbb => self.cp(.E),
            0xbc => self.cp(.H),
            0xbd => self.cp(.L),
            0xbe => self.cp(.P_HL),
            0xfe => self.cp(.N),

            0x3c => self.inc8(.A),
            0x04 => self.inc8(.B),
            0x0c => self.inc8(.C),
            0x14 => self.inc8(.D),
            0x1c => self.inc8(.E),
            0x24 => self.inc8(.H),
            0x2c => self.inc8(.L),
            0x34 => self.inc8(.P_HL),

            0x3d => self.dec8(.A),
            0x05 => self.dec8(.B),
            0x0d => self.dec8(.C),
            0x15 => self.dec8(.D),
            0x1d => self.dec8(.E),
            0x25 => self.dec8(.H),
            0x2d => self.dec8(.L),
            0x35 => self.dec8(.P_HL),

            0x09 => self.add_hl(.BC),
            0x19 => self.add_hl(.DE),
            0x29 => self.add_hl(.HL),
            0x39 => self.add_hl(.SP),
            0xe8 => self.add_sp_n(),

            0x03 => self.inc16(.BC),
            0x13 => self.inc16(.DE),
            0x23 => self.inc16(.HL),
            0x33 => self.inc16(.SP),

            0x0b => self.dec16(.BC),
            0x1b => self.dec16(.DE),
            0x2b => self.dec16(.HL),
            0x3b => self.dec16(.SP),

            0x07 => self.rlc(._A),
            0x17 => self.rl(._A),
            0x0f => self.rrc(._A),
            0x1f => self.rr(._A),

            0x27 => self.daa(),
            0x2f => self.cpl(),
            0x3f => self.ccf(),
            0x37 => self.scf(),
            0xf3 => self.di(),
            0xfb => self.ei(),
            0x76 => self.halt(),
            0x00 => self.nop(),

            0xc3 => self.jp(.Always),
            0xc2 => self.jp(.NotZero),
            0xca => self.jp(.Zero),
            0xd2 => self.jp(.NotCarry),
            0xda => self.jp(.Carry),
            0xe9 => self.jp_p_hl(),
            0x18 => self.jr(.Always),
            0x20 => self.jr(.NotZero),
            0x28 => self.jr(.Zero),
            0x30 => self.jr(.NotCarry),
            0x38 => self.jr(.Carry),
            0xcd => self.call(.Always),
            0xc4 => self.call(.NotZero),
            0xcc => self.call(.Zero),
            0xd4 => self.call(.NotCarry),
            0xdc => self.call(.Carry),
            0xc7 => self.rst(0x00),
            0xcf => self.rst(0x08),
            0xd7 => self.rst(0x10),
            0xdf => self.rst(0x18),
            0xe7 => self.rst(0x20),
            0xef => self.rst(0x28),
            0xf7 => self.rst(0x30),
            0xff => self.rst(0x38),
            0xc9 => self.ret(.Always),
            0xc0 => self.ret(.NotZero),
            0xc8 => self.ret(.Zero),
            0xd0 => self.ret(.NotCarry),
            0xd8 => self.ret(.Carry),
            0xd9 => self.reti(),

            0x10 => {
                const instruction10 = self.fetch8();
                switch (instruction10) {
                    0x00 => self.stop(),
                    else => panic("CPU.dispatch: undefined instruction 0x10 0x{x}", .{instruction10}),
                }
            },

            0xcb => {
                const instructionCB = self.fetch8();
                switch (instructionCB) {
                    0x37 => self.swap(.A),
                    0x30 => self.swap(.B),
                    0x31 => self.swap(.C),
                    0x32 => self.swap(.D),
                    0x33 => self.swap(.E),
                    0x34 => self.swap(.H),
                    0x35 => self.swap(.L),
                    0x36 => self.swap(.P_HL),

                    0x07 => self.rlc(.A),
                    0x00 => self.rlc(.B),
                    0x01 => self.rlc(.C),
                    0x02 => self.rlc(.D),
                    0x03 => self.rlc(.E),
                    0x04 => self.rlc(.H),
                    0x05 => self.rlc(.L),
                    0x06 => self.rlc(.P_HL),

                    0x17 => self.rl(.A),
                    0x10 => self.rl(.B),
                    0x11 => self.rl(.C),
                    0x12 => self.rl(.D),
                    0x13 => self.rl(.E),
                    0x14 => self.rl(.H),
                    0x15 => self.rl(.L),
                    0x16 => self.rl(.P_HL),

                    0x0f => self.rrc(.A),
                    0x08 => self.rrc(.B),
                    0x09 => self.rrc(.C),
                    0x0a => self.rrc(.D),
                    0x0b => self.rrc(.E),
                    0x0c => self.rrc(.H),
                    0x0d => self.rrc(.L),
                    0x0e => self.rrc(.P_HL),

                    0x1f => self.rr(.A),
                    0x18 => self.rr(.B),
                    0x19 => self.rr(.C),
                    0x1a => self.rr(.D),
                    0x1b => self.rr(.E),
                    0x1c => self.rr(.H),
                    0x1d => self.rr(.L),
                    0x1e => self.rr(.P_HL),

                    0x27 => self.sla(.A),
                    0x20 => self.sla(.B),
                    0x21 => self.sla(.C),
                    0x22 => self.sla(.D),
                    0x23 => self.sla(.E),
                    0x24 => self.sla(.H),
                    0x25 => self.sla(.L),
                    0x26 => self.sla(.P_HL),

                    0x2f => self.sra(.A),
                    0x28 => self.sra(.B),
                    0x29 => self.sra(.C),
                    0x2a => self.sra(.D),
                    0x2b => self.sra(.E),
                    0x2c => self.sra(.H),
                    0x2d => self.sra(.L),
                    0x2e => self.sra(.P_HL),

                    0x3f => self.srl(.A),
                    0x38 => self.srl(.B),
                    0x39 => self.srl(.C),
                    0x3a => self.srl(.D),
                    0x3b => self.srl(.E),
                    0x3c => self.srl(.H),
                    0x3d => self.srl(.L),
                    0x3e => self.srl(.P_HL),

                    0x47 => self.bit(0, .A),
                    0x40 => self.bit(0, .B),
                    0x41 => self.bit(0, .C),
                    0x42 => self.bit(0, .D),
                    0x43 => self.bit(0, .E),
                    0x44 => self.bit(0, .H),
                    0x45 => self.bit(0, .L),
                    0x46 => self.bit(0, .P_HL),
                    0x4f => self.bit(1, .A),
                    0x48 => self.bit(1, .B),
                    0x49 => self.bit(1, .C),
                    0x4a => self.bit(1, .D),
                    0x4b => self.bit(1, .E),
                    0x4c => self.bit(1, .H),
                    0x4d => self.bit(1, .L),
                    0x4e => self.bit(1, .P_HL),
                    0x57 => self.bit(2, .A),
                    0x50 => self.bit(2, .B),
                    0x51 => self.bit(2, .C),
                    0x52 => self.bit(2, .D),
                    0x53 => self.bit(2, .E),
                    0x54 => self.bit(2, .H),
                    0x55 => self.bit(2, .L),
                    0x56 => self.bit(2, .P_HL),
                    0x5f => self.bit(3, .A),
                    0x58 => self.bit(3, .B),
                    0x59 => self.bit(3, .C),
                    0x5a => self.bit(3, .D),
                    0x5b => self.bit(3, .E),
                    0x5c => self.bit(3, .H),
                    0x5d => self.bit(3, .L),
                    0x5e => self.bit(3, .P_HL),
                    0x67 => self.bit(4, .A),
                    0x60 => self.bit(4, .B),
                    0x61 => self.bit(4, .C),
                    0x62 => self.bit(4, .D),
                    0x63 => self.bit(4, .E),
                    0x64 => self.bit(4, .H),
                    0x65 => self.bit(4, .L),
                    0x66 => self.bit(4, .P_HL),
                    0x6f => self.bit(5, .A),
                    0x68 => self.bit(5, .B),
                    0x69 => self.bit(5, .C),
                    0x6a => self.bit(5, .D),
                    0x6b => self.bit(5, .E),
                    0x6c => self.bit(5, .H),
                    0x6d => self.bit(5, .L),
                    0x6e => self.bit(5, .P_HL),
                    0x77 => self.bit(6, .A),
                    0x70 => self.bit(6, .B),
                    0x71 => self.bit(6, .C),
                    0x72 => self.bit(6, .D),
                    0x73 => self.bit(6, .E),
                    0x74 => self.bit(6, .H),
                    0x75 => self.bit(6, .L),
                    0x76 => self.bit(6, .P_HL),
                    0x7f => self.bit(7, .A),
                    0x78 => self.bit(7, .B),
                    0x79 => self.bit(7, .C),
                    0x7a => self.bit(7, .D),
                    0x7b => self.bit(7, .E),
                    0x7c => self.bit(7, .H),
                    0x7d => self.bit(7, .L),
                    0x7e => self.bit(7, .P_HL),

                    0xc7 => self.set(0, .A),
                    0xc0 => self.set(0, .B),
                    0xc1 => self.set(0, .C),
                    0xc2 => self.set(0, .D),
                    0xc3 => self.set(0, .E),
                    0xc4 => self.set(0, .H),
                    0xc5 => self.set(0, .L),
                    0xc6 => self.set(0, .P_HL),
                    0xcf => self.set(1, .A),
                    0xc8 => self.set(1, .B),
                    0xc9 => self.set(1, .C),
                    0xca => self.set(1, .D),
                    0xcb => self.set(1, .E),
                    0xcc => self.set(1, .H),
                    0xcd => self.set(1, .L),
                    0xce => self.set(1, .P_HL),
                    0xd7 => self.set(2, .A),
                    0xd0 => self.set(2, .B),
                    0xd1 => self.set(2, .C),
                    0xd2 => self.set(2, .D),
                    0xd3 => self.set(2, .E),
                    0xd4 => self.set(2, .H),
                    0xd5 => self.set(2, .L),
                    0xd6 => self.set(2, .P_HL),
                    0xdf => self.set(3, .A),
                    0xd8 => self.set(3, .B),
                    0xd9 => self.set(3, .C),
                    0xda => self.set(3, .D),
                    0xdb => self.set(3, .E),
                    0xdc => self.set(3, .H),
                    0xdd => self.set(3, .L),
                    0xde => self.set(3, .P_HL),
                    0xe7 => self.set(4, .A),
                    0xe0 => self.set(4, .B),
                    0xe1 => self.set(4, .C),
                    0xe2 => self.set(4, .D),
                    0xe3 => self.set(4, .E),
                    0xe4 => self.set(4, .H),
                    0xe5 => self.set(4, .L),
                    0xe6 => self.set(4, .P_HL),
                    0xef => self.set(5, .A),
                    0xe8 => self.set(5, .B),
                    0xe9 => self.set(5, .C),
                    0xea => self.set(5, .D),
                    0xeb => self.set(5, .E),
                    0xec => self.set(5, .H),
                    0xed => self.set(5, .L),
                    0xee => self.set(5, .P_HL),
                    0xf7 => self.set(6, .A),
                    0xf0 => self.set(6, .B),
                    0xf1 => self.set(6, .C),
                    0xf2 => self.set(6, .D),
                    0xf3 => self.set(6, .E),
                    0xf4 => self.set(6, .H),
                    0xf5 => self.set(6, .L),
                    0xf6 => self.set(6, .P_HL),
                    0xff => self.set(7, .A),
                    0xf8 => self.set(7, .B),
                    0xf9 => self.set(7, .C),
                    0xfa => self.set(7, .D),
                    0xfb => self.set(7, .E),
                    0xfc => self.set(7, .H),
                    0xfd => self.set(7, .L),
                    0xfe => self.set(7, .P_HL),

                    0x87 => self.res(0, .A),
                    0x80 => self.res(0, .B),
                    0x81 => self.res(0, .C),
                    0x82 => self.res(0, .D),
                    0x83 => self.res(0, .E),
                    0x84 => self.res(0, .H),
                    0x85 => self.res(0, .L),
                    0x86 => self.res(0, .P_HL),
                    0x8f => self.res(1, .A),
                    0x88 => self.res(1, .B),
                    0x89 => self.res(1, .C),
                    0x8a => self.res(1, .D),
                    0x8b => self.res(1, .E),
                    0x8c => self.res(1, .H),
                    0x8d => self.res(1, .L),
                    0x8e => self.res(1, .P_HL),
                    0x97 => self.res(2, .A),
                    0x90 => self.res(2, .B),
                    0x91 => self.res(2, .C),
                    0x92 => self.res(2, .D),
                    0x93 => self.res(2, .E),
                    0x94 => self.res(2, .H),
                    0x95 => self.res(2, .L),
                    0x96 => self.res(2, .P_HL),
                    0x9f => self.res(3, .A),
                    0x98 => self.res(3, .B),
                    0x99 => self.res(3, .C),
                    0x9a => self.res(3, .D),
                    0x9b => self.res(3, .E),
                    0x9c => self.res(3, .H),
                    0x9d => self.res(3, .L),
                    0x9e => self.res(3, .P_HL),
                    0xa7 => self.res(4, .A),
                    0xa0 => self.res(4, .B),
                    0xa1 => self.res(4, .C),
                    0xa2 => self.res(4, .D),
                    0xa3 => self.res(4, .E),
                    0xa4 => self.res(4, .H),
                    0xa5 => self.res(4, .L),
                    0xa6 => self.res(4, .P_HL),
                    0xaf => self.res(5, .A),
                    0xa8 => self.res(5, .B),
                    0xa9 => self.res(5, .C),
                    0xaa => self.res(5, .D),
                    0xab => self.res(5, .E),
                    0xac => self.res(5, .H),
                    0xad => self.res(5, .L),
                    0xae => self.res(5, .P_HL),
                    0xb7 => self.res(6, .A),
                    0xb0 => self.res(6, .B),
                    0xb1 => self.res(6, .C),
                    0xb2 => self.res(6, .D),
                    0xb3 => self.res(6, .E),
                    0xb4 => self.res(6, .H),
                    0xb5 => self.res(6, .L),
                    0xb6 => self.res(6, .P_HL),
                    0xbf => self.res(7, .A),
                    0xb8 => self.res(7, .B),
                    0xb9 => self.res(7, .C),
                    0xba => self.res(7, .D),
                    0xbb => self.res(7, .E),
                    0xbc => self.res(7, .H),
                    0xbd => self.res(7, .L),
                    0xbe => self.res(7, .P_HL),
                    //else => panic("CPU.dispatch: undefined instruction 0xcb 0x{x}", .{instructionCB}),
                }
            },

            else => panic("CPU.dispatch: undefined instruction 0x{x}", .{instruction}),
        }
    }

};


