require_relative './boot_basic'

class Benchmarker < BasicBenchmarker
  class << self
    def preload_libs
      super

      require 'datadog'
      require 'pry'
      require_relative 'dogstatsd_reporter'
    end
  end
end
