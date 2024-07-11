require 'net/http'
require "datadog_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

Datadog::Profiling::Loader.install_tracepoint

while true
  begin
    raise('hello')
  rescue
    print '.'
  end
end
