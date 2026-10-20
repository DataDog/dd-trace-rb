#define _GNU_SOURCE
#include <datadog/data-pipeline.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* Pause after the real native result exists, before Ruby regains the GVL. */
ddog_TraceExporterError *ddog_trace_exporter_send_trace_chunks_observed(
    const ddog_TraceExporter *exporter, ddog_TracerTraceChunks *chunks,
    ddog_TraceExporterResponse **response, ddog_TraceExporterObservations *report,
    const ddog_TraceExporterCancelToken *cancel) {
    typedef ddog_TraceExporterError *(*send_fn)(const ddog_TraceExporter *, ddog_TracerTraceChunks *,
        ddog_TraceExporterResponse **, ddog_TraceExporterObservations *, const ddog_TraceExporterCancelToken *);
    void *library = dlopen(getenv("OBSERVATION_LIBRARY"), RTLD_NOW | RTLD_NOLOAD);
    send_fn send = library ? (send_fn)dlsym(library, "ddog_trace_exporter_send_trace_chunks_observed") : NULL;
    if (send == NULL) { fprintf(stderr, "Cannot resolve observed send: %s\n", dlerror()); _exit(20); }

    ddog_TraceExporterError *error = send(exporter, chunks, response, report, cancel);
    char message[256];
    int size = snprintf(message, sizeof(message),
        "{\"requests\":%" PRIu64 ",\"chunks_sent\":%" PRIu64 ",\"bytes_sent\":%" PRIu64
        ",\"chunks_dropped\":%" PRIu64 "}\n",
        report->requests_count, report->chunks_sent, report->bytes_sent, report->chunks_dropped_send_failure);
    if (write(atoi(getenv("OBSERVATION_READY_FD")), message, size) != size) { perror("write"); _exit(21); }

    int fd = atoi(getenv("OBSERVATION_RELEASE_FD"));
    if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) < 0) { perror("fcntl"); _exit(22); }
    char release;
    ssize_t result;
    do { result = read(fd, &release, 1); } while (result < 0 && errno == EINTR);
    if (result != 1) { perror("read"); _exit(23); }
    dlclose(library);
    return error;
}
