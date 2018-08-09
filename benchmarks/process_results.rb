require 'descriptive-statistics'
require 'yaml'

filenames = ARGV

def read_execution_time(filename)
  IO.readlines(filename).last.split(',').first.to_f
end

not_instrumented_times = filenames.select(&/not-instrumented/.method(:match))
                             .map(&method(:read_execution_time))

instrumented_times = filenames.select(&/benchmark-instrumented/.method(:match))
                         .map(&method(:read_execution_time))

def print_stats(data)
  stats = DescriptiveStatistics::Stats.new(data)
  o = {}
  %w{sum mean median variance population_variance}.each do |m|
    o[m] = stats.method(m).call
  end
  puts YAML.dump(o)
end

print_stats(not_instrumented_times)
print_stats(instrumented_times)
