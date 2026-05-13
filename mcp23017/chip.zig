//! MCP23017 – 16-bit I/O Expander with I2C Interface
//! Wokwi Custom Chip · Zig 0.16 (No-std)
//!
//! Datasheet: https://ww1.microchip.com/downloads/en/DeviceDoc/20001952C.pdf
//! SPDX-License-Identifier: MIT

// ─── Wokwi API Types ──────────────────────────────────────────────────────────

/// Opaque pin handle returned by pinInit
const Pin = i32;

/// Opaque I²C device handle returned by i2cInit
const I2cDev = u32;

const PinMode = enum(u32) {
    input = 0,
    output = 1,
    input_pullup = 2,
    input_pulldown = 3,
    analog = 4,
    output_low = 16,
    output_high = 17,
};

const PinValue = enum(u32) {
    low = 0,
    high = 1,
};

const Edge = enum(u32) {
    rising = 1,
    falling = 2,
    both = 3,
};

/// Passed to pinWatch; must stay alive (heap or global) for the simulation.
const PinWatchConfig = extern struct {
    user_data: ?*anyopaque,
    edge: u32,
    pin_change: *const fn (?*anyopaque, Pin, u32) callconv(.c) void,
};

/// Passed to i2cInit; the struct is copied by the host so stack lifetime is fine.
const I2cConfig = extern struct {
    user_data: ?*anyopaque,
    address: u32,
    scl: Pin,
    sda: Pin,
    connect: *const fn (?*anyopaque, u32, bool) callconv(.c) bool,
    read: *const fn (?*anyopaque) callconv(.c) u8,
    write: *const fn (?*anyopaque, u8) callconv(.c) bool,
    disconnect: *const fn (?*anyopaque) callconv(.c) void,
    reserved: [8]u32,
};

// ─── Wokwi Host-Function Imports (become WASM imports from "env") ─────────────

extern fn pinInit(name: [*:0]const u8, mode: u32) Pin;
extern fn pinRead(pin: Pin) u32;
extern fn pinWrite(pin: Pin, value: u32) void;
extern fn pinWatch(pin: Pin, config: *const PinWatchConfig) bool;
extern fn pinMode(pin: Pin, mode: u32) void;
extern fn attrInit(name: [*:0]const u8, default_value: u32) u32;
extern fn attrRead(attr_id: u32) u32;
extern fn i2cInit(config: *const I2cConfig) I2cDev;

// ─── Register Map  (IOCON.BANK = 0, power-on default) ────────────────────────

const R = struct {
    const iodira: u8 = 0x00; // I/O direction Port A  (1=input, 0=output)
    const iodirb: u8 = 0x01; // I/O direction Port B
    const ipola: u8 = 0x02; // Input polarity Port A
    const ipolb: u8 = 0x03; // Input polarity Port B
    const gpintena: u8 = 0x04; // Interrupt-on-change enable Port A
    const gpintenb: u8 = 0x05; // Interrupt-on-change enable Port B
    const defvala: u8 = 0x06; // Default compare Port A
    const defvalb: u8 = 0x07; // Default compare Port B
    const intcona: u8 = 0x08; // Interrupt control Port A (0=change,1=defval)
    const intconb: u8 = 0x09; // Interrupt control Port B
    const iocona: u8 = 0x0A; // Configuration register
    const ioconb: u8 = 0x0B; // (mirrors iocona)
    const gppua: u8 = 0x0C; // Pull-up enable Port A
    const gppub: u8 = 0x0D; // Pull-up enable Port B
    const intfa: u8 = 0x0E; // Interrupt flag Port A   (read-only)
    const intfb: u8 = 0x0F; // Interrupt flag Port B   (read-only)
    const intcapa: u8 = 0x10; // Interrupt captured Port A (read-only)
    const intcapb: u8 = 0x11; // Interrupt captured Port B (read-only)
    const gpioa: u8 = 0x12; // GPIO Port A  (write → olata)
    const gpiob: u8 = 0x13; // GPIO Port B  (write → olatb)
    const olata: u8 = 0x14; // Output latch Port A
    const olatb: u8 = 0x15; // Output latch Port B
    const count: u8 = 0x16; // Total register count
};

/// IOCON register bit masks
const IOCON = struct {
    const bank: u8 = 0x80; // Register bank layout (0 = paired/default)
    const mirror: u8 = 0x40; // Mirror INTA and INTB
    const seqop: u8 = 0x20; // Disable auto-increment when 1
    const odr: u8 = 0x04; // Open-drain INT outputs
    const intpol: u8 = 0x02; // INT polarity (1 = active-high)
};

const BASE_I2C_ADDR: u32 = 0x20;

// ─── Chip State ───────────────────────────────────────────────────────────────

const ChipState = struct {
    i2c: I2cDev = 0,

    // 22-register shadow file
    regs: [R.count]u8 = [_]u8{0} ** R.count,

    // I²C sequential-access pointer
    reg_ptr: u8 = 0,
    has_reg_ptr: bool = false,

    // Resolved I²C address (BASE_I2C_ADDR | A2:A1:A0)
    i2c_addr: u32 = BASE_I2C_ADDR,

    // GPIO pin handles
    gpa: [8]Pin = [_]Pin{0} ** 8, // Port A
    gpb: [8]Pin = [_]Pin{0} ** 8, // Port B

    // Address / control pins
    addr_pins: [3]Pin = [_]Pin{0} ** 3,
    int_a: Pin = 0,
    int_b: Pin = 0,
    reset_pin: Pin = 0,

    // Cached sampled GPIO values (after IPOL flip)
    gpio_a_input: u8 = 0xFF,
    gpio_b_input: u8 = 0xFF,

    // Interrupt state
    int_flag_a: u8 = 0,
    int_flag_b: u8 = 0,
    int_cap_a: u8 = 0,
    int_cap_b: u8 = 0,

    // Debug flags read from diagram.json attrs (kept for logic, removed logs)
    gen_debug: bool = false,
    i2c_debug: bool = false,

    // PinWatchConfig instances must outlive their registration.
    gpio_watch: PinWatchConfig = undefined,
    reset_watch: PinWatchConfig = undefined,
};

// Global static state instead of dynamic allocation
var global_chip: ChipState = undefined;

// ─── chip_init (exported as "chipInit" – called once by Wokwi at startup) ────

export fn chipInit() void {
    const chip = &global_chip;
    chip.* = ChipState{};

    // Read debug attributes (match PCA9685 naming convention)
    const attr_i2c = attrInit("i2c_debug", 0);
    const attr_gen = attrInit("gen_debug", 0);
    chip.i2c_debug = attrRead(attr_i2c) != 0;
    chip.gen_debug = attrRead(attr_gen) != 0;

    // ── Power-on defaults ────────────────────────────────────────────────
    chip.regs[R.iodira] = 0xFF; // all inputs
    chip.regs[R.iodirb] = 0xFF;

    // ── GPIO Port A (GPA0..GPA7) ─────────────────────────────────────────
    const gpa_names = [8][*:0]const u8{
        "GPA0", "GPA1", "GPA2", "GPA3", "GPA4", "GPA5", "GPA6", "GPA7",
    };
    for (&chip.gpa, gpa_names) |*p, name|
        p.* = pinInit(name, @intFromEnum(PinMode.input));

    // ── GPIO Port B (GPB0..GPB7) ─────────────────────────────────────────
    const gpb_names = [8][*:0]const u8{
        "GPB0", "GPB1", "GPB2", "GPB3", "GPB4", "GPB5", "GPB6", "GPB7",
    };
    for (&chip.gpb, gpb_names) |*p, name|
        p.* = pinInit(name, @intFromEnum(PinMode.input));

    // ── Watch all GPIO pins for interrupt-on-change ──────────────────────
    chip.gpio_watch = .{
        .user_data = chip,
        .edge = @intFromEnum(Edge.both),
        .pin_change = onGpioChange,
    };
    for (chip.gpa) |p| _ = pinWatch(p, &chip.gpio_watch);
    for (chip.gpb) |p| _ = pinWatch(p, &chip.gpio_watch);

    // ── INTA / INTB output pins (high-impedance at reset) ────────────────
    chip.int_a = pinInit("INTA", @intFromEnum(PinMode.input));
    chip.int_b = pinInit("INTB", @intFromEnum(PinMode.input));

    // ── RESET pin (active-low) ───────────────────────────────────────────
    chip.reset_pin = pinInit("RESET", @intFromEnum(PinMode.input_pullup));
    chip.reset_watch = .{
        .user_data = chip,
        .edge = @intFromEnum(Edge.both),
        .pin_change = onResetChange,
    };
    _ = pinWatch(chip.reset_pin, &chip.reset_watch);

    // ── Address pins A0, A1, A2 ──────────────────────────────────────────
    const addr_names = [3][*:0]const u8{ "A0", "A1", "A2" };
    for (&chip.addr_pins, addr_names) |*p, name|
        p.* = pinInit(name, @intFromEnum(PinMode.input_pulldown));
    chip.i2c_addr = resolveAddr(chip);

    // ── I²C – address=0 means "listen to all"; we filter in onI2cConnect ─
    const i2c_cfg = I2cConfig{
        .user_data = chip,
        .address = 0,
        .scl = pinInit("SCL", @intFromEnum(PinMode.input)),
        .sda = pinInit("SDA", @intFromEnum(PinMode.input)),
        .connect = onI2cConnect,
        .read = onI2cRead,
        .write = onI2cWrite,
        .disconnect = onI2cDisconnect,
        .reserved = [_]u32{0} ** 8,
    };
    chip.i2c = i2cInit(&i2c_cfg);
}

// ─── Address Resolution ───────────────────────────────────────────────────────

fn resolveAddr(chip: *ChipState) u32 {
    var addr = BASE_I2C_ADDR;
    for (chip.addr_pins, 0..) |p, i| {
        if (pinRead(p) != 0) addr |= @as(u32, 1) << @intCast(i);
    }
    return addr;
}

// ─── Chip Reset ───────────────────────────────────────────────────────────────

fn chipReset(chip: *ChipState) void {
    for (&chip.regs) |*b| b.* = 0;
    chip.regs[R.iodira] = 0xFF;
    chip.regs[R.iodirb] = 0xFF;

    chip.reg_ptr = 0;
    chip.has_reg_ptr = false;
    chip.int_flag_a = 0;
    chip.int_flag_b = 0;
    chip.int_cap_a = 0;
    chip.int_cap_b = 0;

    // Release INT pins (high-impedance)
    pinMode(chip.int_a, @intFromEnum(PinMode.input));
    pinMode(chip.int_b, @intFromEnum(PinMode.input));

    // All GPIO back to input-with-pullup
    for (chip.gpa) |p| pinMode(p, @intFromEnum(PinMode.input));
    for (chip.gpb) |p| pinMode(p, @intFromEnum(PinMode.input));
}

// ─── Pin-Mode / Output-Latch Update ──────────────────────────────────────────

fn updatePinModes(chip: *ChipState) void {
    const dir_a = chip.regs[R.iodira];
    const dir_b = chip.regs[R.iodirb];
    const pup_a = chip.regs[R.gppua];
    const pup_b = chip.regs[R.gppub];
    const lat_a = chip.regs[R.olata];
    const lat_b = chip.regs[R.olatb];

    for (0..8) |i| {
        const bit: u8 = @as(u8, 1) << @intCast(i);

        // Port A
        if (dir_a & bit != 0) {
            const mode: PinMode = if (pup_a & bit != 0) .input_pullup else .input;
            pinMode(chip.gpa[i], @intFromEnum(mode));
        } else {
            pinMode(chip.gpa[i], @intFromEnum(PinMode.output));
            pinWrite(chip.gpa[i], if (lat_a & bit != 0) @intFromEnum(PinValue.high) else @intFromEnum(PinValue.low));
        }

        // Port B
        if (dir_b & bit != 0) {
            const mode: PinMode = if (pup_b & bit != 0) .input_pullup else .input;
            pinMode(chip.gpb[i], @intFromEnum(mode));
        } else {
            pinMode(chip.gpb[i], @intFromEnum(PinMode.output));
            pinWrite(chip.gpb[i], if (lat_b & bit != 0) @intFromEnum(PinValue.high) else @intFromEnum(PinValue.low));
        }
    }
}

// ─── Sample GPIO Inputs ───────────────────────────────────────────────────────

fn sampleInputs(chip: *ChipState) void {
    const dir_a = chip.regs[R.iodira];
    const dir_b = chip.regs[R.iodirb];
    const ipol_a = chip.regs[R.ipola];
    const ipol_b = chip.regs[R.ipolb];
    const lat_a = chip.regs[R.olata];
    const lat_b = chip.regs[R.olatb];

    var raw_a: u8 = 0;
    var raw_b: u8 = 0;

    for (0..8) |i| {
        const bit: u8 = @as(u8, 1) << @intCast(i);
        raw_a |= if (dir_a & bit != 0)
            (if (pinRead(chip.gpa[i]) != 0) bit else 0)
        else
            (lat_a & bit);

        raw_b |= if (dir_b & bit != 0)
            (if (pinRead(chip.gpb[i]) != 0) bit else 0)
        else
            (lat_b & bit);
    }

    chip.gpio_a_input = raw_a ^ (ipol_a & dir_a);
    chip.gpio_b_input = raw_b ^ (ipol_b & dir_b);
}

// ─── Interrupt Logic ──────────────────────────────────────────────────────────

fn checkInterrupts(chip: *ChipState) void {
    const gpintena = chip.regs[R.gpintena];
    const gpintenb = chip.regs[R.gpintenb];
    if (gpintena == 0 and gpintenb == 0) return;

    sampleInputs(chip);

    const intcona = chip.regs[R.intcona];
    const intconb = chip.regs[R.intconb];
    const defvala = chip.regs[R.defvala];
    const defvalb = chip.regs[R.defvalb];

    var new_flag_a: u8 = 0;
    var new_flag_b: u8 = 0;

    for (0..8) |i| {
        const bit: u8 = @as(u8, 1) << @intCast(i);

        // Port A
        if (gpintena & bit != 0 and chip.regs[R.iodira] & bit != 0) {
            const cur = (chip.gpio_a_input & bit) != 0;
            const prev = (chip.int_cap_a & bit) != 0;
            const def = (defvala & bit) != 0;
            const trig = if (intcona & bit != 0) (cur != def) else (cur != prev);
            if (trig) new_flag_a |= bit;
        }

        // Port B
        if (gpintenb & bit != 0 and chip.regs[R.iodirb] & bit != 0) {
            const cur = (chip.gpio_b_input & bit) != 0;
            const prev = (chip.int_cap_b & bit) != 0;
            const def = (defvalb & bit) != 0;
            const trig = if (intconb & bit != 0) (cur != def) else (cur != prev);
            if (trig) new_flag_b |= bit;
        }
    }

    if (new_flag_a != 0 and chip.int_flag_a == 0) {
        chip.int_flag_a = new_flag_a;
        chip.int_cap_a = chip.gpio_a_input;
        chip.regs[R.intfa] = chip.int_flag_a;
        chip.regs[R.intcapa] = chip.int_cap_a;
    }
    if (new_flag_b != 0 and chip.int_flag_b == 0) {
        chip.int_flag_b = new_flag_b;
        chip.int_cap_b = chip.gpio_b_input;
        chip.regs[R.intfb] = chip.int_flag_b;
        chip.regs[R.intcapb] = chip.int_cap_b;
    }

    driveIntPins(chip);
}

fn driveIntPins(chip: *ChipState) void {
    const iocon = chip.regs[R.iocona];
    const mirror = (iocon & IOCON.mirror) != 0;
    const open_drain = (iocon & IOCON.odr) != 0;
    const active_hi = (iocon & IOCON.intpol) != 0;

    var act_a = chip.int_flag_a != 0;
    var act_b = chip.int_flag_b != 0;
    if (mirror) {
        act_a = act_a or act_b;
        act_b = act_a;
    }

    driveOneInt(chip.int_a, act_a, open_drain, active_hi);
    driveOneInt(chip.int_b, act_b, open_drain, active_hi);
}

inline fn driveOneInt(pin: Pin, active: bool, open_drain: bool, active_hi: bool) void {
    if (open_drain) {
        if (active) {
            if (active_hi) {
                pinMode(pin, @intFromEnum(PinMode.input));
            } else {
                pinMode(pin, @intFromEnum(PinMode.output));
                pinWrite(pin, @intFromEnum(PinValue.low));
            }
        } else {
            pinMode(pin, @intFromEnum(PinMode.input));
        }
    } else {
        pinMode(pin, @intFromEnum(PinMode.output));
        const level: PinValue = if (active == active_hi) .high else .low;
        pinWrite(pin, @intFromEnum(level));
    }
}

fn clearIntA(chip: *ChipState) void {
    chip.int_flag_a = 0;
    chip.regs[R.intfa] = 0;
    sampleInputs(chip);
    chip.int_cap_a = chip.gpio_a_input;
    chip.regs[R.intcapa] = chip.int_cap_a;
    driveIntPins(chip);
}

fn clearIntB(chip: *ChipState) void {
    chip.int_flag_b = 0;
    chip.regs[R.intfb] = 0;
    sampleInputs(chip);
    chip.int_cap_b = chip.gpio_b_input;
    chip.regs[R.intcapb] = chip.int_cap_b;
    driveIntPins(chip);
}

// ─── Register Write ───────────────────────────────────────────────────────────

fn writeReg(chip: *ChipState, reg: u8, val: u8) void {
    if (reg >= R.count) return;

    switch (reg) {
        R.iodira => {
            chip.regs[R.iodira] = val;
            updatePinModes(chip);
        },
        R.iodirb => {
            chip.regs[R.iodirb] = val;
            updatePinModes(chip);
        },
        R.gppua => {
            chip.regs[R.gppua] = val;
            updatePinModes(chip);
        },
        R.gppub => {
            chip.regs[R.gppub] = val;
            updatePinModes(chip);
        },
        R.gpioa => {
            chip.regs[R.olata] = val;
            updatePinModes(chip);
        },
        R.gpiob => {
            chip.regs[R.olatb] = val;
            updatePinModes(chip);
        },
        R.olata => {
            chip.regs[R.olata] = val;
            updatePinModes(chip);
        },
        R.olatb => {
            chip.regs[R.olatb] = val;
            updatePinModes(chip);
        },
        R.iocona, R.ioconb => {
            const masked = val & ~IOCON.bank;
            chip.regs[R.iocona] = masked;
            chip.regs[R.ioconb] = masked;
        },
        R.intfa, R.intfb, R.intcapa, R.intcapb => {},
        else => chip.regs[reg] = val,
    }
}

// ─── Register Read ────────────────────────────────────────────────────────────

fn readReg(chip: *ChipState, reg: u8) u8 {
    if (reg >= R.count) return 0;

    const val: u8 = switch (reg) {
        R.gpioa => blk: {
            sampleInputs(chip);
            if (chip.int_flag_a != 0) clearIntA(chip);
            break :blk chip.gpio_a_input;
        },
        R.gpiob => blk: {
            sampleInputs(chip);
            if (chip.int_flag_b != 0) clearIntB(chip);
            break :blk chip.gpio_b_input;
        },
        R.intcapa => blk: {
            const v = chip.regs[R.intcapa];
            if (chip.int_flag_a != 0) clearIntA(chip);
            break :blk v;
        },
        R.intcapb => blk: {
            const v = chip.regs[R.intcapb];
            if (chip.int_flag_b != 0) clearIntB(chip);
            break :blk v;
        },
        else => chip.regs[reg],
    };

    return val;
}

// ─── I²C Callbacks ────────────────────────────────────────────────────────────

fn onI2cConnect(user_data: ?*anyopaque, address: u32, read: bool) callconv(.c) bool {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));

    // Filter: only accept our resolved hardware address
    if (address != chip.i2c_addr) return false; // NACK

    if (!read) {
        chip.has_reg_ptr = false;
    }
    return true; // ACK
}

fn onI2cRead(user_data: ?*anyopaque) callconv(.c) u8 {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));
    const val = readReg(chip, chip.reg_ptr);

    if (chip.regs[R.iocona] & IOCON.seqop == 0)
        chip.reg_ptr = (chip.reg_ptr +% 1) % R.count;

    return val;
}

fn onI2cWrite(user_data: ?*anyopaque, byte: u8) callconv(.c) bool {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));

    if (!chip.has_reg_ptr) {
        chip.reg_ptr = byte % R.count;
        chip.has_reg_ptr = true;
    } else {
        writeReg(chip, chip.reg_ptr, byte);
        if (chip.regs[R.iocona] & IOCON.seqop == 0)
            chip.reg_ptr = (chip.reg_ptr +% 1) % R.count;
    }
    return true; // ACK
}

fn onI2cDisconnect(user_data: ?*anyopaque) callconv(.c) void {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));
    chip.has_reg_ptr = false;
}

// ─── Pin-Change Callbacks ─────────────────────────────────────────────────────

fn onGpioChange(user_data: ?*anyopaque, pin: Pin, value: u32) callconv(.c) void {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));
    _ = pin;
    _ = value;
    if (chip.regs[R.gpintena] != 0 or chip.regs[R.gpintenb] != 0)
        checkInterrupts(chip);
}

fn onResetChange(user_data: ?*anyopaque, pin: Pin, value: u32) callconv(.c) void {
    const chip: *ChipState = @ptrCast(@alignCast(user_data));
    _ = pin;
    if (value == 0) chipReset(chip); // RESET is active-low
}
