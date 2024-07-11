require 'net/http'

# Datadog::Profiling.wait_until_running
require 'datadog/profiling/load_native_extension'

Datadog::Profiling::NativeExtension.install_weird_tracepoint

# thread = Thread.new do
  while true
    begin
      Net::HTTP.get('127.0.0.10', '/index.html')
    rescue => e
      print '.'
    end
    Thread.pass
  end
# end

# sleep 1
# thread.kill
# thread.join

# puts "Finished!"
