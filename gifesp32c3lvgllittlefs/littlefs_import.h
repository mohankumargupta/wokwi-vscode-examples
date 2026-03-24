// littlefs_setup.h
#pragma once

#include "esp_littlefs.h"
#include "dirent.h"
#include "cstring"

// Helper function to list files recursively
void list_files(const char *path, int depth = 0) {
    DIR *dir = opendir(path);
    if (!dir) {
        ESP_LOGW("fs", "Failed to open directory %s", path);
        return;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        // Skip hidden files/system entries if desired, though LittleFS usually doesn't have them
        if (entry->d_name[0] == '.') continue;

        // Build full path
        char full_path[512];
        snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);

        if (entry->d_type == DT_DIR) {
            // It's a directory, print name and recurse
            ESP_LOGI("fs", "%*s[%s]", depth * 2, "", entry->d_name);
            list_files(full_path, depth + 1);
        } else {
            // It's a file, print name
            ESP_LOGI("fs", "%*s- %s", depth * 2, "", entry->d_name);
        }
    }
    closedir(dir);
}

