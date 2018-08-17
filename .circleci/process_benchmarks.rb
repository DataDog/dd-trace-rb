require 'descriptive-statistics'
require 'yaml'

filenames = ARGV

def read_execution_time(filename)
    IO.readlines(filename).last.split(',').first.to_f
  end

times = filenames.map(&method(:read_execution_time))

def print_stats(data)
    stats = DescriptiveStatistics::Stats.new(data)
    o = {}
    %w{sum mean median variance population_variance}.each do |m|
        o[m] = stats.method(m).call
      end
    puts YAML.dump(o)
  end

print_stats(times)
