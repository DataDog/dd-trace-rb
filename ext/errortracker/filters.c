#include <ruby.h>
#include "datadog_ruby_common.h"
#include "filters.h"

VALUE generate_filter(DDTRACE_UNUSED VALUE _self, VALUE to_instrument) {
  const char *to_instrument_cstr = StringValueCStr(to_instrument);
  if (strcmp(to_instrument_cstr, "all") == 0) {
    return rb_proc_new((VALUE(*)(ANYARGS))_proc_filter_all, Qnil);
  } else if (strcmp(to_instrument_cstr, "user") == 0) {
    return rb_proc_new((VALUE(*)(ANYARGS))_proc_filter_user, Qnil);
  } else if (strcmp(to_instrument_cstr, "third_party") == 0) {
    return rb_proc_new((VALUE(*)(ANYARGS))_proc_filter_third_party, Qnil);
  } else {
    rb_raise(rb_eRuntimeError, "ErrorTracker: invalid value '%+"PRIsVALUE"' for 'to_instrument' option. Expected 'all', 'user', or 'third_party'.", to_instrument);
  }
}

VALUE _get_filename(VALUE raised_exc) {
  VALUE backtrace = rb_funcall(raised_exc, rb_intern("backtrace"), 0);
  VALUE first_line = rb_ary_entry(backtrace, 0);
  VALUE parts = rb_str_split(first_line, ":");
  return rb_ary_entry(parts, 0);
}

VALUE _get_gem_name(VALUE file_name) {
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

VALUE _proc_filter_all(VALUE raised_exc) {
  VALUE file_name = _get_filename(raised_exc);
  VALUE includes_ddtrace = rb_funcall(file_name, rb_intern("include?"), 1, rb_str_new_cstr("ddtrace"));
  return !RB_TEST(includes_ddtrace);
}

VALUE _proc_filter_user(VALUE raised_exc) {
  VALUE file_name = _get_filename(raised_exc);
  // If there is no gem_name -> return Qnil so !RB_TEST = Qtrue
  return !RB_TEST(_get_gem_name(file_name));
}

VALUE _proc_filter_third_party(VALUE raised_exc) {
  VALUE file_name = _get_filename(raised_exc);
  VALUE includes_ddtrace = rb_funcall(file_name, rb_intern("include?"), 1, rb_str_new_cstr("ddtrace"));
  return !RB_TEST(includes_ddtrace) && RB_TEST(_get_gem_name(file_name));
}
