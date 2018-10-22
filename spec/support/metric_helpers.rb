module MetricHelpers
  # RSpec matcher for generic Statsd metric
  class SendStat < RSpec::Mocks::Matchers::HaveReceived
    def initialize(method_name, *args, &block)
      super(method_name, &block)
      @args = args
    end

    def name
      'send_stat'
    end

    def matches?(subject, &block)
      @constraints << with_constraint
      super
    end

    def does_not_match?(subject, &block)
      @constraints << with_constraint
      super
    end

    def with(*args)
      with_constraint.concat(args)
      self
    end

    protected

    def with_constraint
      @with_constraint ||= [
        'with',
        *@args
      ]
    end
  end

  # RSpec matcher for Statsd#increment
  class IncrementStat < SendStat
    def initialize(stat, &block)
      super(:increment, &block)
      @stat = stat
    end

    def name
      'increment_stat'
    end

    def with(*args)
      with_constraint[2] = merge_with_defaults(args.first)
      self
    end

    protected

    def with_constraint
      @with_constraint ||= [
        'with',
        @stat,
        Datadog::Metrics::DEFAULT_OPTIONS
      ]
    end

    private

    def merge_with_defaults(options)
      if options.nil?
        # Set default options
        Datadog::Metrics::DEFAULT_OPTIONS.dup
      else
        # Add tags to options
        options.dup.tap do |opts|
          opts[:tags] = if opts.key?(:tags)
                          opts[:tags].dup.concat(Datadog::Metrics::DEFAULT_TAGS)
                        else
                          Datadog::Metrics::DEFAULT_TAGS.dup
                        end
        end
      end
    end
  end

  def send_stat(*args)
    SendStat.new(*args)
  end

  def increment_stat(*args)
    IncrementStat.new(*args)
  end

  shared_context 'metric counts' do
    let(:statsd) { spy('statsd') } # TODO: Make this an instance double.
    let(:stats) { Hash.new(0) }
    let(:stats_mutex) { Mutex.new }

    before(:each) do
      allow(statsd).to receive(:increment) do |name, options = {}|
        stats_mutex.synchronize do
          stats[name] = 0 unless stats.key?(name)
          stats[name] += options.key?(:by) ? options[:by] : 1
        end
      end
    end
  end
end
