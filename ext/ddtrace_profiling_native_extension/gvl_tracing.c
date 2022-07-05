#include <ruby.h>
#include <ruby/thread.h>
#include <pthread.h>
#include <sys/time.h>

static VALUE _native_start(VALUE self);
static VALUE _native_stop(VALUE self);
static void render_event(int event_id);

static FILE *output_file = NULL;
static rb_internal_thread_event_hook_t *current_hook = NULL;
static long start_tracing_monotonic_timestamp = 0;
static long start_tracing_epoch_nanos = 0;

static const char *READY = "ready";
static const char *RESUMED = "resumed";
static const char *SUSPENDED = "suspended";
static const char *STARTED = "started";
static const char *EXITED = "exited";
static const char *TRACING_STARTED = "started_tracing";
static const char *TRACING_STOPPED = "stopped_tracing";

#define GVL_TRACING_STARTED 1 << 5
#define GVL_TRACING_STOPPED 1 << 6

void gvl_tracing_init(VALUE profiling_module) {
  VALUE gvl_tracing_class = rb_define_class_under(profiling_module, "GvlTracing", rb_cObject);

  rb_define_singleton_method(gvl_tracing_class, "_native_start", _native_start, 0);
  rb_define_singleton_method(gvl_tracing_class, "_native_stop", _native_stop, 0);
}

#ifdef HAVE_RB_INTERNAL_THREAD_ADD_EVENT_HOOK
  static void on_gvl_event(rb_event_flag_t event, const rb_internal_thread_event_data_t *_unused1, void *_unused2) {
    render_event(event);
  }
#endif

static VALUE _native_start(VALUE self) {
  if (output_file != NULL) {
    rb_raise(rb_eRuntimeError, "Already started");
  }

  output_file = fopen("gvl_tracing_out.json", "w");
  if (output_file == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to open file");
  }

  fprintf(output_file, "[\n");

  #ifdef HAVE_RB_INTERNAL_THREAD_ADD_EVENT_HOOK
    render_event(GVL_TRACING_STARTED);
    render_event(RUBY_INTERNAL_THREAD_EVENT_RESUMED);
    current_hook = rb_internal_thread_add_event_hook(
      on_gvl_event,
      (
        RUBY_INTERNAL_THREAD_EVENT_READY | RUBY_INTERNAL_THREAD_EVENT_RESUMED | RUBY_INTERNAL_THREAD_EVENT_SUSPENDED |
        RUBY_INTERNAL_THREAD_EVENT_STARTED | RUBY_INTERNAL_THREAD_EVENT_EXITED
      ),
      NULL
    );
  #endif

  return Qtrue;
}

static VALUE _native_stop(VALUE self) {
  if (output_file == NULL) {
    rb_raise(rb_eRuntimeError, "Not started");
  }

  #ifdef HAVE_RB_INTERNAL_THREAD_ADD_EVENT_HOOK
    rb_internal_thread_remove_event_hook(current_hook);
    render_event(GVL_TRACING_STOPPED);
    render_event(GVL_TRACING_STOPPED); // Hack just to have time "range" for the stopped event, so it shows in the output
  #endif

  fprintf(output_file, "  []\n]\n");
  fclose(output_file);

  return Qtrue;
}

static void render_event(int event_id) {
  struct timespec current_time;
  if (clock_gettime(CLOCK_MONOTONIC, &current_time) < 0) {
    fprintf(stderr, "Error getting time :(\n");
    return;
  }

  if (event_id == GVL_TRACING_STARTED) {
    struct timeval current_time_epoch;
    if (gettimeofday(&current_time_epoch, NULL) < 0) {
      fprintf(stderr, "Error getting time :(\n");
      return;
    }
    start_tracing_epoch_nanos = (current_time_epoch.tv_sec * 1000 * 1000 * 1000) + (current_time_epoch.tv_usec * 1000);
  }

  long timestamp = current_time.tv_nsec + (current_time.tv_sec * 1000 * 1000 * 1000);
  pthread_t thread_id = pthread_self();

  if (event_id == GVL_TRACING_STARTED) {
    start_tracing_monotonic_timestamp = timestamp;
  }

  const char *event_name = "";
  switch (event_id) {
    case RUBY_INTERNAL_THREAD_EVENT_READY:
      event_name = READY;
      break;
    case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
      event_name = RESUMED;
      break;
    case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
      event_name = SUSPENDED;
      break;
    case RUBY_INTERNAL_THREAD_EVENT_STARTED:
      event_name = STARTED;
      break;
    case RUBY_INTERNAL_THREAD_EVENT_EXITED:
      event_name = EXITED;
      break;
    case GVL_TRACING_STARTED:
      event_name = TRACING_STARTED;
      break;
    case GVL_TRACING_STOPPED:
      event_name =TRACING_STOPPED;
      break;
  };

  long timestamp_since_epoch = (timestamp - start_tracing_monotonic_timestamp) + start_tracing_epoch_nanos;

  fprintf(output_file, "  [%lu, %lu, \"%s\"],\n", thread_id, timestamp_since_epoch, event_name);
}
