
#ifdef RUBY_MJIT_HEADER
  // Pick up internal structures from the private Ruby MJIT header file
  #include RUBY_MJIT_HEADER
#else
  // The MJIT header was introduced on 2.6 and removed on 3.3; for other Rubies we rely on
  // the debase-ruby_core_source gem to get access to private VM headers.

  // We can't do anything about warnings in VM headers, so we just use this technique to suppress them.
  // See https://nelkinda.com/blog/suppress-warnings-in-gcc-and-clang/#d11e364 for details.
  #pragma GCC diagnostic push
  #pragma GCC diagnostic ignored "-Wunused-parameter"
  #pragma GCC diagnostic ignored "-Wattributes"
  #pragma GCC diagnostic ignored "-Wpragmas"
  #pragma GCC diagnostic ignored "-Wexpansion-to-defined"
    #include <vm_core.h>
  #pragma GCC diagnostic pop

  #include <ruby.h>

  #ifndef NO_RACTOR_HEADER_INCLUDE
    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wunused-parameter"
      #include <ractor_core.h>
    #pragma GCC diagnostic pop
  #endif
#endif

void ddtrace_print_offsets(void) {
  fprintf(stderr, "rb_thread_t.nt:     %ld\n", __builtin_offsetof(rb_thread_t, nt));
  fprintf(stderr, "rb_thread_t.ractor: %ld\n", __builtin_offsetof(rb_thread_t, ractor));
  fprintf(stderr, "rb_thread_t.ec:     %ld\n", __builtin_offsetof(rb_thread_t, ec));
  fprintf(stderr, "rb_thread_t.status: %ld\n", __builtin_offsetof(rb_thread_t, status));
}
