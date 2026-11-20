#include <ruby.h>
#include <errno.h>
#include <libproc.h>
#include <mach/vm_prot.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

static bool region_at(uintptr_t address, struct proc_regioninfo *region) {
  int bytes = proc_pidinfo(getpid(), PROC_PIDREGIONINFO, address, region, sizeof(*region));
  return bytes == sizeof(*region) && !(region->pri_flags & PROC_REGION_SUBMAP) &&
    address >= region->pri_address && address - region->pri_address < region->pri_size;
}

static int willneed_error(uintptr_t start, size_t length) {
  return madvise((void *)start, length, MADV_WILLNEED) == 0 ? 0 : errno;
}

static VALUE check_stack_guard(VALUE self, VALUE name) {
  const char *label = StringValueCStr(name);
  char on_stack;
  struct proc_regioninfo stack, guard;
  size_t page_size = (size_t)getpagesize();
  if (!region_at((uintptr_t)&on_stack, &stack) || !region_at(stack.pri_address - 1, &guard) ||
      !(stack.pri_protection & VM_PROT_WRITE) || guard.pri_protection != VM_PROT_NONE ||
      stack.pri_size < page_size || guard.pri_size < page_size) {
    fprintf(stderr, "FAIL %s: could not locate a writable stack immediately above a PROT_NONE guard\n", label);
    return Qnil;
  }

  int writable_error = willneed_error(stack.pri_address, page_size);
  int guard_error = willneed_error(stack.pri_address - page_size, 2 * page_size);
  fprintf(stderr, "%s %s: writable page error=%d (expected 0), guard + writable page error=%d (expected EPERM=%d)\n",
    writable_error == 0 && guard_error == EPERM ? "PASS" : "FAIL", label, writable_error, guard_error, EPERM);
  return Qnil;
}

RUBY_FUNC_EXPORTED void Init_stack_guard(void) {
  rb_define_global_function("check_stack_guard", check_stack_guard, 1);
}
