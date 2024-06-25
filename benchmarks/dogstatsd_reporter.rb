require 'datadog'
require 'datadog/statsd'
require 'benchmark/ips'
require 'securerandom'

# Implements a benchmark-ips "suite" that reports benchmark data via DogStatsD
#
# To use it, pass it in as the `suite:` setting when configuring benchmark-ips, e.g.:
#
# ```ruby
# Benchmark.ips do |x|
#   x.config(suite: report_to_dogstatsd_if_enabled_via_environment_variable(...settings...))
# ```

REPORTING_DISABLED_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new

def report_to_dogstatsd_if_enabled_via_environment_variable(**args)
  if ENV['REPORT_TO_DOGSTATSD'] == 'true'
    puts "DogStatsD reporting ✅ enabled"
    DogstatsdReporter.new(**args)
  else
    REPORTING_DISABLED_ONLY_ONCE.run { puts "DogStatsD reporting ❌ disabled" }
    nil
  end
end

class DogstatsdReporter
  private

  attr_reader :benchmark_name
  attr_reader :commit_id
  attr_reader :statsd
  attr_reader :run_id

  public

  def initialize(
    benchmark_name:,
    commit_id: commit_id_from_env,
    statsd: Datadog::Statsd.new(ENV['DD_AGENT_HOST'] || 'localhost', 8125)
  )
    @benchmark_name = benchmark_name
    @commit_id = commit_id
    @statsd = statsd
    @run_id = SecureRandom.uuid

    at_exit { close }
  end

  def add_report(report, *_)
    puts "Reporting #{report}"
    statsd.gauge(
      'perf.benchmark',
      report.stats.central_tendency,
      tags: to_tags(
        'perf.benchmark.name': benchmark_name,
        'perf.benchmark.report': report.label,
        'perf.benchmark.run_id': run_id,
        'tracer_version': commit_id,
      )
    )
  end

  def close
    statsd.close
    puts "Finished sending data to DogStatsD"
  end

  # Unused, but called by benchmark-ips
  def warming(a, b); end
  def warmup_stats(a, b); end
  def running(a, b); end

  private

  def to_tags(hash)
    hash.map { |tag, value| "#{tag}:#{value}" }
  end

  def commit_id_from_env
    ENV.fetch('LATEST_COMMIT_ID') { raise 'Please set the LATEST_COMMIT_ID environment variable when reporting to DogStatsD' }
  end
end
