require_relative './boot_basic'
require 'datadog'

class Benchmarker < BasicBenchmarker
  class << self
    def preload_libs
      super

      require 'datadog'
      require 'pry'
      require_relative 'dogstatsd_reporter'
    end
  end

  REPORTING_DISABLED_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new

  def suite_for_dogstatsd_reporting(**args)
    if ENV['REPORT_TO_DOGSTATSD'] == 'true'
      puts "DogStatsD reporting ✅ enabled"
      require_relative 'dogstatsd_reporter'
      DogstatsdReporter.new(**args)
    else
      REPORTING_DISABLED_ONLY_ONCE.run { puts "DogStatsD reporting ❌ disabled" }
      nil
    end
  end
end
