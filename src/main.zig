const std = @import("std");
const process = std.process;
const print = std.debug.print;

const ROM = @import("rom.zig").ROM;
const MBC1 = @import("mbc.zig").MBC1;
const Logger = @import("logger.zig").Logger;
const CPU = @import("cpu.zig").CPU;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //const allocator = gpa.allocator();

    var argIter = try std.process.argsWithAllocator(gpa.allocator());
    var path: []const u8 = "rom/gb_test_roms/cpu_instrs/cpu_instrs.gb";
    if (argIter.skip()) {
        if (argIter.next()) |arg| {
            path = arg;
        }
    }

    const rom = try ROM.readFile(gpa.allocator(), path);
    print("{s} {}\n", .{rom.title, rom.cartrige_type});

    var mbc1 = MBC1.init(gpa.allocator(), &rom);
    var mbc = &mbc1.mbc;

    var logger = try Logger.init();

    var cpu = CPU.init(mbc, &logger); 

    var stdin = std.io.getStdIn().reader();
    var isCreateDumpFile = false;
    while (true) {
        print("$ ", .{});
        var buf: [100]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line_| {
            const line = line_[0 .. line_.len - 1];
            if (eqStr(line, "serial") or eqStr(line, "s")) {
                print("Serial:\n{s}\n", .{cpu.serial_buffer});
            } else if (eqStr(line, "print") or eqStr(line, "p")) {
                if (logger.is_print) {
                    print("Print off\n", .{});
                    logger.is_print = false;
                } else {
                    print("Print on\n", .{});
                    logger.is_print = true;
                }
            } else if (eqStr(line, "dump") or eqStr(line, "d")) {
                if (!isCreateDumpFile) {
                   try logger.createFile("./log.txt");
                   logger.logFmt("{s} {}\n", .{rom.title, rom.cartrige_type});
                   defer {
                       logger.flush() catch {
                           print("error. logger.flush\n", .{});
                       };
                   }

                   isCreateDumpFile = true;
                } else {
                    if (logger.is_dump) {
                        print("Dump off\n", .{});
                        try logger.flush();
                        logger.is_dump = false;
                    } else {
                        print("Dump on\n", .{});
                        try logger.flush();
                        logger.is_dump = true;
                    }
                }
            } else if (eqStr(line, "memory") or eqStr(line, "m")) {
                try showMemory(&cpu);
            } else if (eqStr(line, "cpu") or eqStr(line, "c")) {
                const p = logger.is_print;
                logger.is_print = true;
                cpu.log("DEBUG", .None, .None, .none);
                logger.is_print = p;
            } else if (eqStr(line, "quit") or eqStr(line, "q")) {
                break;
            } else if (eqStr(line, "nop") or eqStr(line, "n")) {
                while (true) {
                    if (cpu.mbc.read(cpu.pc) == 0) {
                        const p = logger.is_print;
                        logger.is_print = true;
                        cpu.step();
                        logger.is_print = p;
                        break;
                    }
                    cpu.step();
                }
           } else {
                const n = std.fmt.parseInt(usize, line, 10) catch 0;
                const p = logger.is_print;
                if (n != 0) {
                    var i: usize = 0;
                    while (i < n - 1) : (i += 1) {
                        if (i % 3000000 == 0) {
                            logger.is_print = true;
                            cpu.step();
                            logger.is_print = p;
                            print("Serial:\n{s}\n", .{cpu.serial_buffer});
                        } else {
                            cpu.step();
                        }
                    }
                    logger.is_print = true;
                    cpu.step();
                    logger.is_print = p;
                } else {
                    logger.is_print = true;
                    cpu.step();
                    logger.is_print = p;
                }
            }
        }
    }
}

fn eqStr(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a) |_,i| {
        if (a[i] != b [i]) {
            return false;
        }
    }
    return true;
}

fn showMemory(cpu: *CPU) !void {
    var i: usize = 0;
    while (i < 0xffff) : (i += 0x10) {
        var buf = [1]u8{0} ** 0x50;
        var j: usize = 0;
        while (j < 0x10 * 3) : (j += 3) {
            _ = try std.fmt.bufPrint(buf[j..j+3], "{x:0>2} ", .{cpu.mbc.read(@intCast(u16, i+(j/3)))});
        }
        print("{X:0>4}: {s}\n", .{i, buf});
    }
}
