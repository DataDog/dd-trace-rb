# Profiling Native Extension Design

The profiling native extension is used to implement features which are expensive (in terms of resources) or otherwise
impossible to implement using Ruby code.

This extension is quite coupled with MRI Ruby ("C Ruby") internals, and is not intended to support other rubies such as
JRuby or TruffleRuby. When below we say "Ruby", read it as "MRI Ruby".

## Disabling

The profiling native extension can be disabled by setting `DD_PROFILING_NO_EXTENSION=true` when installing or running
the gem. Setting `DD_PROFILING_NO_EXTENSION` at installation time skips compilation of the extension entirely.

(If you're a customer and needed to use this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>.)

Currently the profiler can still "limp along" when the native extension is disabled, but the plan is to require it
in future releases -- e.g. disabling the extension will disable profiling entirely.

## Safety

The profiling native extension is (and must always be) designed to **not cause failures** during gem installation, even
if some features, Ruby versions, or operating systems are not supported.

E.g. the extension must cleanly build on Ruby 2.1 on Windows, even if at run time it will effectively do nothing for
such a setup.

We have a CI setup to help validate this, but this is really important to keep in mind when adding to or changing the
existing codebase.

## Usage of private VM headers

To implement some of the features below, we sometimes require access to private Ruby header files (that describe VM
internal types, structures and functions).

Because these private header files are not included in regular Ruby installations, our current workaround is to piggy
back on a special header that Ruby includes that is only intended for use by the Ruby MJIT compiler. This header is
placed inside the `include/` directory in a Ruby installation, and is named for that specific Ruby version. e.g.
`rb_mjit_min_header-2.7.4.h`.

This header was introduced by the first Ruby version that added MJIT, which is 2.6+.

For older Ruby versions (see safety section above), this header is not available, and this must be handled gracefully.

Functions which make use of these headers are defined in the <private_vm_api_acccess.c> file.

## Feature: Getting thread CPU-time clock_ids

* **OS support**: Linux
* **Ruby support**: 2.6+

To enable CPU-time profiling, we use the `pthread_getcpuclockid(pthread_t thread, clockid_t *clockid)` C function to
obtain a `clockid_t` that can then be used with the `Process.clock_gettime` method (or directly with the
`clock_gettime()` C function).

The challenge with using `pthread_getcpuclockid()` is that we need to get the `pthread_t` for a given Ruby `Thread`
object. We previously did this with a weird combination of monkey patching and `pthread_self()` (effectively patching
every `Thread` to run `pthread_self()` at initialization time and stash that value somewhere), but this had a number
of downsides.

The approach we use in the profiling native extension is to reach inside the internal structure of the `Thread` object,
and extract the `pthread_t` that Ruby itself keeps, but does not expose. This is implemented in the `pthread_id_for()`
function in `private_vm_api_acccess.c`. Thus, using this trick we can at any point in execution go from a `Thread`
object into the `clockid_t` that we need.

Note that `pthread_getcpuclockid()` is not available on macOS (nor, obviously, on Windows), and hence this feature
is currently Linux-specific. Thus, in the <clock_id_from_pthread.c> file we implement the feature for supported Ruby
setups but if something is missing we instead compile in <clock_id_noop.c> that includes a no-op implementation of the
feature.
