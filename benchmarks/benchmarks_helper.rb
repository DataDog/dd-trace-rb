require 'benchmark/ips'
require 'datadog'
require 'pry'

module JobReporter
  def report(name, *args, **opts, &block)
    caller_path = caller_locations.first.path
    prefix = File.basename(caller_path).sub(/_.*\z/, '')
    name = "#{prefix} - #{name}"
    # Older Rubies (e.g. 2.5) do not permit passing *args and &block
    # in the same invocation.
    if args.any? && block_given?
      raise ArgumentError, 'Unsupported usage'
    elsif block_given?
      if opts.any?
        super(name, **opts, &block)
      else
        super(name, &block)
      end
    else
      super(name, *args, **opts)
    end
  end
end

class Benchmark::IPS::Job
  prepend JobReporter
end
