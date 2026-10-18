# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative "benchmarks_helper"
require "datadog"
require "datadog/tracing/contrib/utils/rds_endpoint"

# Measures what reading an Amazon RDS endpoint hostname costs a database span.
#
# The figure that matters most is "host is not an RDS endpoint": every database span in
# every application that does not use RDS pays it, so the gate in front of the parser is
# built to make it cost nothing and allocate nothing. The cached figure is what an
# application on RDS pays per span after the first one, and the uncached figure is what it
# pays for each endpoint it has not seen before.
class RDSEndpointBenchmark
  RDS_ENDPOINT = "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com"
  RDS_READER_ENDPOINT = "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com"
  NON_RDS_HOST = "db.internal.example.com"
  LOCALHOST = "localhost"

  # More distinct endpoints than the parser's cache holds, so stepping through them keeps
  # missing it and measures a cold parse plus an eviction rather than a lookup.
  UNCACHED_ENDPOINTS = Array.new(1024) { |i| "db#{i}.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

  # @param [Integer] time in seconds. The default is 12 seconds. Because benchmark-ips tries to
  # run one iteration per 100ms, this means we'll have around 120 samples
  # (give or take a small margin of error).
  # @param [Integer] warmup in seconds. The default is 2 seconds.
  def benchmark_time(time: 12, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: time, warmup: warmup}
  end

  def initialize
    @parser = Datadog::Tracing::Contrib::Utils::RDSEndpoint
    @span = Datadog::Tracing::SpanOperation.new("benchmark")
    @uncached_index = 0
  end

  def benchmark_parse
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("parse - host is not an RDS endpoint") do
        @parser.parse(NON_RDS_HOST)
      end

      x.report("parse - host is not a hostname") do
        @parser.parse(LOCALHOST)
      end

      x.report("parse - RDS instance endpoint, cached") do
        @parser.parse(RDS_ENDPOINT)
      end

      x.report("parse - RDS reader endpoint, cached") do
        @parser.parse(RDS_READER_ENDPOINT)
      end

      x.report("parse - RDS instance endpoint, not yet cached") do
        @parser.parse(UNCACHED_ENDPOINTS[@uncached_index])
        @uncached_index = (@uncached_index + 1) % UNCACHED_ENDPOINTS.length
      end

      x.save! "#{File.basename(__FILE__, ".rb")}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  # What the mysql2, pg, trilogy, Sequel, and Active Record integrations actually call.
  def benchmark_annotate
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("annotate! - host is not an RDS endpoint") do
        @parser.annotate!(@span, NON_RDS_HOST)
      end

      x.report("annotate! - RDS instance endpoint") do
        @parser.annotate!(@span, RDS_ENDPOINT)
      end

      x.save! "#{File.basename(__FILE__, ".rb")}-annotate-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

RDSEndpointBenchmark.new.instance_exec do
  benchmark_parse
  benchmark_annotate
end
