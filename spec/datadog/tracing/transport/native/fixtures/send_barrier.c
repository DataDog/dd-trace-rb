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
ddog_TraceExporterError *ddog_trace_exporter_send_trace_chunks_batched(
    const ddog_TraceExporter *exporter, ddog_TracerTraceChunks *chunks,
    size_t max_payload_bytes, ddog_TraceExporterBatch **batch,
    const ddog_TraceExporterCancelToken *cancel) {
    typedef ddog_TraceExporterError *(*send_fn)(const ddog_TraceExporter *, ddog_TracerTraceChunks *,
        size_t, ddog_TraceExporterBatch **, const ddog_TraceExporterCancelToken *);
    void *library = dlopen(getenv("OBSERVATION_LIBRARY"), RTLD_NOW | RTLD_NOLOAD);
    send_fn send = library ? (send_fn)dlsym(library, "ddog_trace_exporter_send_trace_chunks_batched") : NULL;
    if (send == NULL) { fprintf(stderr, "Cannot resolve observed send: %s\n", dlerror()); _exit(20); }

    ddog_TraceExporterError *error = send(exporter, chunks, max_payload_bytes, batch, cancel);
    typedef ddog_TraceExporterBatchPayload (*payload_fn)(const ddog_TraceExporterBatch *, size_t);
    payload_fn get_payload = (payload_fn)dlsym(library, "ddog_trace_exporter_batch_payload");
    if (get_payload == NULL) { fprintf(stderr, "Cannot resolve batch accessor\n"); _exit(20); }
    ddog_TraceExporterBatchPayload payload = get_payload(*batch, 0);
    const ddog_TraceExporterObservations *report = &payload.observations;
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
