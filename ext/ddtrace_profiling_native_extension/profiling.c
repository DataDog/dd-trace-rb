#include <ruby.h>
#include <ruby/debug.h>
#include <signal.h>
#include <sys/time.h>

#define MAX_STACK_DEPTH 400 // FIXME: Need to handle when this is not enough
#define SAMPLE_INTERVAL_MS 1000 // TODO: make interval configurable

static VALUE native_working_p(VALUE self);
static VALUE sample_threads();
static VALUE sample_thread(VALUE thread);
static VALUE to_sample(int frames_count, VALUE* frames, int* lines);
static VALUE start_profiler(VALUE self);
// signal handler has to have the following signature - see https://man7.org/linux/man-pages/man2/sigaction.2.html
void prof_signal_handler(int sig, siginfo_t *info, void *ucontext);

// From borrowed_from_ruby.c
int borrowed_from_ruby_sources_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines);
VALUE thread_id_for(VALUE thread);

// From Ruby internal.h
int ruby_thread_has_gvl_p(void);

void Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "sample_threads", sample_threads, 0);
  rb_define_singleton_method(native_extension_module, "start_profiler", start_profiler, 0);
}

static VALUE native_working_p(VALUE self) {
  return Qtrue;
}

//
// - Register a listener so that each time interval, we sample the threads
// - Add signal handler callbacks that call sample_threads
// - Push each result array into a recorder (probably inside listener)
//
static VALUE start_profiler(VALUE self) {
  VALUE sample_interval = INT2FIX(SAMPLE_INTERVAL_MS);
  struct itimerval prof_timer;

  // From stackprof and https://man7.org/linux/man-pages/man2/sigaction.2.html
  // sets up inputs to signal handler register function
  struct sigaction sa;
  sa.sa_sigaction = prof_signal_handler;
  sa.sa_flags = SA_RESTART | SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  // Note: SIGALRM = wall/clock time, SIGPROF = cpu time
  // see - https://www.gnu.org/software/libc/manual/html_node/Alarm-Signals.html
  sigaction(SIGALRM, &sa, NULL); // start with wall time by default
  // https://linux.die.net/man/2/setitimer
  prof_timer.it_interval.tv_sec = 0;
  prof_timer.it_interval.tv_usec = NUM2LONG(sample_interval);
  prof_timer.it_value = prof_timer.it_interval;
  setitimer(ITIMER_REAL, &prof_timer, 0);
  return Qtrue;
}


void prof_signal_handler(int sig, siginfo_t *info, void *ucontext) {
  printf("waking up, trying to sample threads");
  VALUE samples = sample_threads();
  // do something with samples, like add them to the recorder buffer...
}

static VALUE sample_threads() {
  if (!ruby_thread_has_gvl_p()) {
    rb_fatal("Expected to have GVL");
  }

  VALUE threads = rb_funcall(rb_cThread, rb_intern("list"), 0);
  VALUE samples = rb_ary_new();

  for (int i = 0; i < RARRAY_LEN(threads); i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    VALUE result = sample_thread(thread);

    rb_ary_push(samples, result);
  }

  return samples;
}

static VALUE sample_thread(VALUE thread) {
  VALUE frames[MAX_STACK_DEPTH];
  int lines[MAX_STACK_DEPTH];

  int stack_depth = borrowed_from_ruby_sources_rb_profile_frames(thread, 0, MAX_STACK_DEPTH, frames, lines);
  VALUE stack = to_sample(stack_depth, frames, lines);
  VALUE thread_id = thread_id_for(thread);

  return rb_ary_new_from_args(3, thread, thread_id, stack);
}

static VALUE to_sample(int frames_count, VALUE* frames, int* lines) {
  VALUE result = rb_ary_new();

  for (int i = 0; i < frames_count; i++) {
    rb_ary_push(result,
      rb_ary_new_from_args(3, rb_profile_frame_path(frames[i]), rb_profile_frame_full_label(frames[i]), INT2FIX(lines[i]))
    );
  }

  return result;
}
