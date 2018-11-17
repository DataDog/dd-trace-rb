#ifndef GC_H
#define GC_H 1

void gc_enter(rb_event_flag_t flag, VALUE data, VALUE self, ID mid, VALUE klass);
void gc_exit(rb_event_flag_t flag, VALUE data, VALUE self, ID mid, VALUE klass);

#endif /* GC_H */
