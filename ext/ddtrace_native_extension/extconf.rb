require 'mkmf'

# TODO: Should not be hardcoded for my machine
dir_config("libddprof", "/Users/ivo.anjo/datadog/libddprof/include", "/Users/ivo.anjo/datadog/libddprof/target/release")

find_header("ddprof/exporter.h") || raise
find_library("ddprof_exporter", "ddprof_exporter_send") || raise

create_makefile 'ddtrace_native_extension'
