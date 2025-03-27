#include <ruby.h>
#include "datadog_ruby_common.h"
#include "filters.h"

// static VALUE _get_filename(VALUE raised_exc) {
//   VALUE backtrace = rb_funcall(raised_exc, rb_intern("backtrace"), 0);
//   VALUE first_line = rb_ary_entry(backtrace, -1);
//   VALUE parts = rb_str_split(first_line, ":");
//   return rb_ary_entry(parts, 0);
// }

static VALUE _get_gem_name(VALUE file_name) {
  ENFORCE_TYPE(file_name, T_STRING);

  const char *path = StringValueCStr(file_name);
  const char *gems_str = "gems/";
  const char *gems_pos = strstr(path, gems_str);

  if (gems_pos == NULL) {
    return Qfalse;
  }
  const char *gem_path = gems_pos + strlen(gems_str);
  const char *dash_pos = strchr(gem_path, '-');
  if (dash_pos == NULL) {
    return Qfalse;
  }
  long gem_name_len = dash_pos - gem_path;
  VALUE gem_name = rb_str_new(gem_path, gem_name_len);

  VALUE gem_module = rb_const_get(rb_cObject, rb_intern("Gem"));
  VALUE spec_class = rb_const_get(gem_module, rb_intern("Specification"));
  return rb_funcall(spec_class, rb_intern("find_by_name"), 1, gem_name);
}

static VALUE _is_user_code(VALUE rescue_file_path) {
  // If there is no gem_name -> return Qnil so !RB_TEST = Qtrue
  return !RB_TEST(_get_gem_name(rescue_file_path));
}

static VALUE _is_third_party(VALUE rescue_file_path) {
  VALUE includes_ddtrace = rb_funcall(rescue_file_path, rb_intern("include?"), 1, rb_str_new_cstr("ddtrace"));
  return !RB_TEST(includes_ddtrace) && RB_TEST(_get_gem_name(rescue_file_path));
}

static VALUE _is_instrumented_modules(VALUE rescue_file_path, VALUE instrumented_files) {
  return RB_TEST(rb_hash_lookup(instrumented_files, rescue_file_path) != Qnil);
}

static VALUE _proc_filter_all(VALUE rescue_file_path) {
  VALUE includes_ddtrace = rb_funcall(rescue_file_path, rb_intern("include?"), 1, rb_str_new_cstr("ddtrace"));
  return !RB_TEST(includes_ddtrace);
}

static VALUE _proc_filter_user(VALUE rescue_file_path) {
  return _is_user_code(rescue_file_path);
}

static VALUE _proc_filter_third_party(VALUE rescue_file_path) {
  return _is_third_party(rescue_file_path);
}

static VALUE _proc_filter_modules(VALUE rescue_file_path, VALUE instrumented_files) {
  return _is_instrumented_modules(rescue_file_path, instrumented_files);
}

static VALUE _proc_filter_user_and_modules(VALUE rescue_file_path, VALUE instrumented_files) {
  return _is_user_code(rescue_file_path) || _is_instrumented_modules(rescue_file_path, instrumented_files);
}

static VALUE _proc_filter_third_party_and_modules(VALUE rescue_file_path, VALUE instrumented_files) {
  return _is_third_party(rescue_file_path) || _is_instrumented_modules(rescue_file_path, instrumented_files);
}


VALUE generate_filter(DDTRACE_UNUSED VALUE _self, VALUE to_instrument, VALUE instrumented_files) {
  const char *to_instrument_cstr = StringValueCStr(to_instrument);
  VALUE (*proc_func)(ANYARGS) = NULL;

  if (strcmp(to_instrument_cstr, "all") == 0) {
    proc_func = _proc_filter_all;
  } else if (strcmp(to_instrument_cstr, "user") == 0) {
    proc_func = (instrumented_files == Qnil)
                ? (VALUE(*)(ANYARGS))_proc_filter_user
                : (VALUE(*)(ANYARGS))_proc_filter_user_and_modules;
  } else if (strcmp(to_instrument_cstr, "third_party") == 0) {
    proc_func = (instrumented_files == Qnil)
                ? (VALUE(*)(ANYARGS))_proc_filter_third_party
                : (VALUE(*)(ANYARGS))_proc_filter_third_party_and_modules;
  } else if (instrumented_files != Qnil) {
    proc_func = _proc_filter_modules;
  } else {
    rb_raise(rb_eRuntimeError, "ErrorTracker: invalid value '%+"PRIsVALUE"' for 'to_instrument' option. Expected 'all', 'user', or 'third_party'.", to_instrument);
  }

  return rb_proc_new((VALUE(*)(ANYARGS))proc_func, instrumented_files);
}