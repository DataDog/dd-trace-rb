// Used to mark function arguments that are deliberately left unused
#ifdef __GNUC__
  #define DDTRACE_UNUSED  __attribute__((unused))
#else
  #define DDTRACE_UNUSED
#endif

#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))

void DDTRACE_EXPORT Init_libdatadog_api(void) {

}
