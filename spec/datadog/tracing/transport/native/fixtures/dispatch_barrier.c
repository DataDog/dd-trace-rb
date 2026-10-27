#define _GNU_SOURCE
#include <datadog/data-pipeline.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* Declared here to avoid compiling against Ruby headers; stable since Ruby 2.0. */
void *rb_thread_call_without_gvl2(void *(*func)(void *), void *data1, void (*ubf)(void *), void *data2);
void rb_thread_check_ints(void);

static int released;

static void *wait_for_release(void *unused) {
    (void)unused;
    if (write(atoi(getenv("OBSERVATION_READY_FD")), "{}\n", 3) != 3) { perror("write"); _exit(21); }
    int fd = atoi(getenv("OBSERVATION_RELEASE_FD"));
    if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) < 0) { perror("fcntl"); _exit(22); }
    char release;
    ssize_t result;
    do { result = read(fd, &release, 1); } while (result < 0 && errno == EINTR);
    if (result != 1) { perror("read"); _exit(23); }
    released = 1;
    return NULL;
}

static void ignore_interrupt(void *unused) { (void)unused; }

/* Token creation is the last step before dispatch. Unlike the plain variant, the gvl2 wait
 * leaves an interrupt received meanwhile pending, so the send's own gvl2 call never runs it. */
ddog_TraceExporterCancelToken *ddog_trace_exporter_cancel_token_new(void) {
    typedef ddog_TraceExporterCancelToken *(*new_fn)(void);
    void *library = dlopen(getenv("OBSERVATION_LIBRARY"), RTLD_NOW | RTLD_NOLOAD);
    new_fn create = library ? (new_fn)dlsym(library, "ddog_trace_exporter_cancel_token_new") : NULL;
    if (create == NULL) { fprintf(stderr, "Cannot resolve token creation: %s\n", dlerror()); _exit(20); }

    /* A timer interrupt can skip the wait; no test interrupt is sent before the ready signal. */
    while (!released) {
        rb_thread_call_without_gvl2(wait_for_release, NULL, ignore_interrupt, NULL);
        if (!released) rb_thread_check_ints();
    }
    ddog_TraceExporterCancelToken *token = create();
    dlclose(library);
    return token;
}
