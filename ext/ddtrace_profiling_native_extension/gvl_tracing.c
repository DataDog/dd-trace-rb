#include <ruby.h>
#include <ruby/thread.h>
#include <pthread.h>

static VALUE _native_start(VALUE self);
static VALUE _native_stop(VALUE self);
static void render_event(int event_id);

static FILE *output_file = NULL;
static rb_internal_thread_event_hook_t *current_hook = NULL;

static const char *READY = "ready";
static const char *RESUMED = "resumed";
static const char *SUSPENDED = "suspended";
// static const char *STARTED = "started";
// static const char *EXITED = "exited";

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
    current_hook = rb_internal_thread_add_event_hook(
      on_gvl_event,
      (
        RUBY_INTERNAL_THREAD_EVENT_READY | RUBY_INTERNAL_THREAD_EVENT_RESUMED | RUBY_INTERNAL_THREAD_EVENT_SUSPENDED //|
        // RUBY_INTERNAL_THREAD_EVENT_STARTED | RUBY_INTERNAL_THREAD_EVENT_EXITED
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
  #endif

  fprintf(output_file, "  []\n]\n");
  fclose(output_file);

  return Qtrue;
}

static void render_event(int event_id) {
  struct timespec current_time;
  if (clock_gettime(CLOCK_MONOTONIC, &current_time) < 0) {
    fprintf(stderr, "Error getting time :(\n");
  }

  long timestamp = current_time.tv_nsec + (current_time.tv_sec * 1000 * 1000 * 1000);
  pthread_t thread_id = pthread_self();

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
    // case RUBY_INTERNAL_THREAD_EVENT_STARTED:
    //   event_name = STARTED;
    //   break;
    // case RUBY_INTERNAL_THREAD_EVENT_EXITED:
    //   event_name = EXITED;
    //   break;
  };

  fprintf(output_file, "  [%lu, %lu, \"%s\"],\n", thread_id, timestamp, event_name);
}
