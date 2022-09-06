const std = @import("std");

pub inline fn toU16(h: u8, l: u8) u16 {
    return @intCast(u16, h) << 8 | @intCast(u16, l);
}

pub inline fn sepU16(hl: u16) struct { h: u8, l: u8 } {
    return .{ .h = @intCast(u8, hl >> 8), .l = @intCast(u8, hl & 0xff) };
}

inline fn bitOpType(comptime T: type) type {
    const U = switch (T) {
        u8 => u3,
        u16 => u4,
        else => u8
    };
    return U;
}

pub inline fn bitSet(comptime T: type, b: T, n: T) T {
    const U = bitOpType(T);
    return b | (@as(T,1) << @intCast(U, n));
}

pub inline fn bitClear(comptime T: type, b: T, n: T) T {
    const U = bitOpType(T);
    return b & ~(@as(T,1) << @intCast(U,n));
}

pub inline fn bitCheck(comptime T: type, b: T, n: T) bool {
    const U = bitOpType(T);
    return (b >> @intCast(U,n)) & 1 == 1;
}

pub const Registers = enum(u16) {
    JOYP = 0xff00,

    SB = 0xff01,
    SC = 0xff02,

    DIV = 0xff04,
    TIMA = 0xff05,
    TMA = 0xff06,
    TAC = 0xff07,

    NR10 = 0xff10,
    NR11 = 0xff11,
    NR12 = 0xff12,
    NR13 = 0xff13,
    NR14 = 0xff14,
    NR21 = 0xff16,
    NR22 = 0xff17,
    NR23 = 0xff18,
    NR24 = 0xff19,
    NR30 = 0xff1a,
    NR31 = 0xff1b,
    NR32 = 0xff1c,
    NR33 = 0xff1d,
    NR34 = 0xff1e,
    NR41 = 0xff20,
    NR42 = 0xff21,
    NR43 = 0xff22,
    NR44 = 0xff23,
    NR50 = 0xff24,
    NR51 = 0xff25,
    NR52 = 0xff26,
    WPR = 0xff30,

    LCDC = 0xff40,
    STAT = 0xff41,
    SCY = 0xff42,
    SCX = 0xff43,
    LY = 0xff44,
    LYC = 0xff45,
    WY = 0xff4a,
    WX = 0xff4b,
    BGP = 0xff47,
    OBP0 = 0xff48,
    OBP1 = 0xff49,
    BCPS = 0xff68,
    BCPD = 0xff69,
    OCPS = 0xff6a,
    DMA = 0xff46,
    VBK = 0xff4f,
    HDMA1 = 0xff51,
    HDMA2 = 0xff52,
    HDMA3 = 0xff53,
    HDMA4 = 0xff54,
    HDMA5 = 0xff55,

    IF = 0xff0f,
    IE = 0xffff,
};
