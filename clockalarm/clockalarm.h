#pragma once

#include <string>
#include <ctime>
#include "esphome/core/time.h"
#include "esphome/components/time/posix_tz.h"

inline std::string format_timezone_time(time_t utc, const char *tz_str, const char *fmt = "%H:%M")
{
    // 1. Parse the target POSIX timezone string
    esphome::time::ParsedTimezone tz;
    if (!esphome::time::parse_posix_tz(tz_str, tz)) {
        return "--:--"; // Fallback if parsing fails
    }

    // 2. Convert UTC epoch into a struct tm shifted for the target timezone
    struct tm tm_buf;
    if (!esphome::time::epoch_to_local_tm(utc, tz, &tm_buf)) {
        return "--:--";
    }

    // 3. Format the struct tm into a string (safe to use as long as fmt doesn't use %Z/%z)
    char out[32];
    strftime(out, sizeof(out), fmt, &tm_buf);

    return std::string(out);
}


