require 'ddtrace/profiling'

if Datadog::Profiling.supported? && Datadog::Profiling.native_cpu_time_supported?
  Datadog::Profiling::Tasks::Setup.new.run
else
  puts '[DDTRACE] Profiling not supported; skipping preload.'
end
