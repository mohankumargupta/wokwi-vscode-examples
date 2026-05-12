const std = @import("std");
const wokwi = @import("wokwi_api.zig");

// const Chip = extern struct {
//     pin_in: wokwi.PinId,
//     pin_out: wokwi.PinId,
// };

pub export fn chipInit() callconv(.c) void {
    wokwi.debugPrint("Hello Zig!\n");
}
