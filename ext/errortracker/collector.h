#ifndef EXT_ERRORTRACKER_COLLECTOR_H
#define EXT_ERRORTRACKER_COLLECTOR_H

#include <ruby.h>

void collector_init(VALUE errortracking_module);
VALUE add_span_event(VALUE self, VALUE span_id, VALUE error, VALUE span_event);
VALUE get_span_events(VALUE self, VALUE span_id);
VALUE _clear_span(VALUE self, VALUE span_id);
VALUE initialize(VALUE self);

#endif // EXT_ERRORTRACKER_COLLECTOR_H
