require_relative 'support/boot'

require 'shellwords'

# This benchmark needs to be run in a clean environment where datadog is
# not loaded yet.
#
# Now that this benchmark is in its own file, it does not need
# to spawn a subprocess IF we would always execute this benchmark
# file by itself.
#
# The gem loading benchmark has never reported results to dogstatsd.
Benchmarker.define do
  # Gem loading is quite slower than the other microbenchmarks
  benchmark 'gem loading', time: 60 do
    code = <<-E
      if defined?(Datadog)
        unless Datadog.constants == [:VERSION]
          STDERR.puts "Datadog already loaded in the target process"
          exit 1
        end
      end

      require 'datadog'

      unless defined?(Datadog::Core)
        STDERR.puts "Datadog::Core not defined"
        exit 1
      end

      exit 0
    E

    rv = system("ruby -e #{Shellwords.shellescape(code)}")
    unless rv
      raise "Gem loading failed"
    end
  end
end
