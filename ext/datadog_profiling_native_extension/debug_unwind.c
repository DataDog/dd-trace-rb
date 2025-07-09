#define UNW_LOCAL_ONLY

#include <libunwind.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Structure to hold information for each frame.
struct frame_info {
    unw_word_t ip;
    char func_name[256];
};

void print_stacktrace_debug(const char *target1, const char *target2, const char *target3) {
    // If no targets are provided, do nothing.
    if (!target1 && !target2 && !target3)
        return;

    struct frame_info frames[100];
    int frame_count = 0;

    unw_cursor_t cursor;
    unw_context_t context;
    unw_getcontext(&context);
    unw_init_local(&cursor, &context);

    // Unwind and store stack frames.
    while (unw_step(&cursor) > 0 && frame_count < 100) {
        unw_word_t ip;
        if (unw_get_reg(&cursor, UNW_REG_IP, &ip) != 0)
            continue;
        frames[frame_count].ip = ip;
        if (unw_get_proc_name(&cursor, frames[frame_count].func_name,
                              sizeof(frames[frame_count].func_name), &ip) != 0) {
            strncpy(frames[frame_count].func_name, "unknown", sizeof(frames[frame_count].func_name));
        }
        frame_count++;
    }

    // Check if any of the provided target function names are present in the stack.
    int found_target1 = 0, found_target2 = 0, found_target3 = 0;
    for (int i = 0; i < frame_count; i++) {
        if (target1 && !found_target1 && strstr(frames[i].func_name, target1))
            found_target1 = 1;
        if (target2 && !found_target2 && strstr(frames[i].func_name, target2))
            found_target2 = 1;
        if (target3 && !found_target3 && strstr(frames[i].func_name, target3))
            found_target3 = 1;
    }

    int total_targets = (target1 ? 1 : 0) + (target2 ? 1 : 0) + (target3 ? 1 : 0);
    int found_targets = found_target1 + found_target2 + found_target3;

    // Only print the stack trace if at least one target function name was found.
    if (found_targets == 0)
        return;

    // Retrieve the executable's path (Linux-specific).
    char exe_path[1024] = "/home/ivo.anjo/.rvm/rubies/ruby-2.7.2/lib/libruby.so.2.7";/*
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len != -1)
        exe_path[len] = '\0';
    else
        strcpy(exe_path, "unknown");*/

    // Print each frame with file and line info using addr2line.
    for (int i = 0; i < frame_count; i++) {
        char cmd[2048];
        char addr2line_output[256] = "??:0";
        /*snprintf(cmd, sizeof(cmd), "addr2line -f -e %s %lx", exe_path, (unsigned long)frames[i].ip);
        FILE *fp = popen(cmd, "r");
        if (fp) {
            if (fgets(addr2line_output, sizeof(addr2line_output), fp) != NULL) {
                size_t n = strlen(addr2line_output);
                if (n > 0 && addr2line_output[n - 1] == '\n')
                    addr2line_output[n - 1] = '\0';
            }
            pclose(fp);
        }*/
        fprintf(stderr, "#%d: [%lx] %s at %s\n", i, (unsigned long)frames[i].ip, frames[i].func_name, addr2line_output);
    }

    // If all provided target function names were found, abort the process.
    if (found_targets == total_targets)
        abort();
}
