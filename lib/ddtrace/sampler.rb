require 'forwardable'

require 'ddtrace/ext/priority'
require 'ddtrace/diagnostics/health'

module Datadog
  # \Sampler performs client-side trace sampling.
  class Sampler
    def sample?(_span)
      raise NotImplementedError, 'Samplers must implement the #sample? method'
    end

    def sample!(_span)
      raise NotImplementedError, 'Samplers must implement the #sample! method'
    end

    def sample_rate(span)
      raise NotImplementedError, 'Samplers must implement the #sample_rate method'
    end
  end

  # \AllSampler samples all the traces.
  class AllSampler < Sampler
    def sample?(span)
      true
    end

    def sample!(span)
      span.sampled = true
    end

    def sample_rate(*_)
      1.0
    end
  end

  # \RateSampler is based on a sample rate.
  class RateSampler < Sampler
    KNUTH_FACTOR = 1111111111111111111
    SAMPLE_RATE_METRIC_KEY = '_sample_rate'.freeze

    # Initialize a \RateSampler.
    # This sampler keeps a random subset of the traces. Its main purpose is to
    # reduce the instrumentation footprint.
    #
    # * +sample_rate+: the sample rate as a \Float between 0.0 and 1.0. 0.0
    #   means that no trace will be sampled; 1.0 means that all traces will be
    #   sampled.
    def initialize(sample_rate = 1.0)
      unless sample_rate > 0.0 && sample_rate <= 1.0
        Datadog.logger.error('sample rate is not between 0 and 1, disabling the sampler')
        sample_rate = 1.0
      end

      self.sample_rate = sample_rate
    end

    def sample_rate(*_)
      @sample_rate
    end

    def sample_rate=(sample_rate)
      @sample_rate = sample_rate
      @sampling_id_threshold = sample_rate * Span::EXTERNAL_MAX_ID
    end

    def sample?(span)
      ((span.trace_id * KNUTH_FACTOR) % Datadog::Span::EXTERNAL_MAX_ID) <= @sampling_id_threshold
    end

    def sample!(span)
      (span.sampled = sample?(span)).tap do |sampled|
        span.set_metric(SAMPLE_RATE_METRIC_KEY, @sample_rate) if sampled
      end
    end
  end

  # Samples at different rates by key.
  class RateByKeySampler < Sampler
    attr_reader \
      :default_key

    def initialize(default_key, default_rate = 1.0, &block)
      raise ArgumentError, 'No resolver given!' unless block_given?

      @default_key = default_key
      @resolver = block
      @mutex = Mutex.new
      @samplers = {}

      set_rate(default_key, default_rate)
    end

    def resolve(span)
      @resolver.call(span)
    end

    def default_sampler
      @samplers[default_key]
    end

    def sample?(span)
      key = resolve(span)

      @mutex.synchronize do
        @samplers.fetch(key, default_sampler).sample?(span)
      end
    end

    def sample!(span)
      key = resolve(span)

      @mutex.synchronize do
        @samplers.fetch(key, default_sampler).sample!(span)
      end
    end

    def sample_rate(span)
      key = resolve(span)

      @mutex.synchronize do
        @samplers.fetch(key, default_sampler).sample_rate
      end
    end

    def update(key, rate)
      @mutex.synchronize do
        set_rate(key, rate)
      end
    end

    def update_all(rate_by_key)
      @mutex.synchronize do
        rate_by_key.each { |key, rate| set_rate(key, rate) }
      end
    end

    def delete(key)
      @mutex.synchronize do
        @samplers.delete(key)
      end
    end

    def delete_if(&block)
      @mutex.synchronize do
        @samplers.delete_if(&block)
      end
    end

    def length
      @samplers.length
    end

    private

    def set_rate(key, rate)
      @samplers[key] ||= RateSampler.new(rate)
      @samplers[key].sample_rate = rate
    end
  end

  # \RateByServiceSampler samples different services at different rates
  class RateByServiceSampler < RateByKeySampler
    DEFAULT_KEY = 'service:,env:'.freeze

    def initialize(default_rate = 1.0, options = {})
      super(DEFAULT_KEY, default_rate, &method(:key_for))
      @env = options[:env]
    end

    def update(rate_by_service)
      # Remove any old services
      delete_if { |key, _| key != DEFAULT_KEY && !rate_by_service.key?(key) }

      # Update each service rate
      update_all(rate_by_service)

      # Emit metric for service cache size
      Datadog.health_metrics.sampling_service_cache_length(length)
    end

    private

    def key_for(span)
      # Resolve env dynamically, if Proc is given.
      env = @env.is_a?(Proc) ? @env.call : @env

      "service:#{span.service},env:#{env}"
    end
  end

  # \PrioritySampler
  class PrioritySampler
    extend Forwardable

    attr_reader :pre_sampler, :priority_sampler

    SAMPLE_RATE_METRIC_KEY = '_sample_rate'.freeze

    def initialize(opts = {})
      @pre_sampler = opts[:base_sampler] || AllSampler.new
      @priority_sampler = opts[:post_sampler] || RateByServiceSampler.new
    end

    def sample?(span)
      @pre_sampler.sample?(span)
    end

    def sample!(span)
      # If pre-sampling is configured, do it first. (By default, this will sample at 100%.)
      # NOTE: Pre-sampling at rates < 100% may result in partial traces; not recommended.
      span.sampled = pre_sample?(span) ? @pre_sampler.sample!(span) : true

      if span.sampled
        # If priority sampling has already been applied upstream, use that, otherwise...
        unless priority_assigned_upstream?(span)
          # Roll the dice and determine whether how we set the priority.
          priority = priority_sample!(span) ? Datadog::Ext::Priority::AUTO_KEEP : Datadog::Ext::Priority::AUTO_REJECT

          assign_priority!(span, priority)
        end
      else
        # If discarded by pre-sampling, set "reject" priority, so other
        # services for the same trace don't sample needlessly.
        assign_priority!(span, Datadog::Ext::Priority::AUTO_REJECT)
      end

      span.sampled
    end

    def_delegators :@priority_sampler, :update

    private

    def pre_sample?(span)
      case @pre_sampler
      when RateSampler
        @pre_sampler.sample_rate < 1.0
      when RateByServiceSampler
        @pre_sampler.sample_rate(span) < 1.0
      else
        true
      end
    end

    def priority_assigned_upstream?(span)
      span.context && !span.context.sampling_priority.nil?
    end

    def priority_sample!(span)
      preserving_sampling(span) do
        @priority_sampler.sample!(span)
      end
    end

    # Ensures the span is always propagated to the writer and that
    # the sample rate metric represents the true client-side sampling.
    def preserving_sampling(span)
      pre_sample_rate_metric = span.get_metric(SAMPLE_RATE_METRIC_KEY)

      yield.tap do
        # NOTE: We'll want to leave `span.sampled = true` here; all spans for priority sampling must
        #       be sent to the agent. Otherwise metrics for traces will not be accurate, since the
        #       agent will have an incomplete dataset.
        #
        #       We also ensure that the agent knows we that our `post_sampler` is not performing true sampling,
        #       to avoid erroneous metric upscaling.
        span.sampled = true
        if pre_sample_rate_metric
          # Restore true sampling metric, as only the @pre_sampler can reject traces
          span.set_metric(SAMPLE_RATE_METRIC_KEY, pre_sample_rate_metric)
        else
          # If @pre_sampler is not enable, sending this metric would be misleading
          span.clear_metric(SAMPLE_RATE_METRIC_KEY)
        end
      end
    end

    def assign_priority!(span, priority)
      if span.context
        span.context.sampling_priority = priority
      else
        # Set the priority directly on the span instead, since otherwise
        # it won't receive the appropriate tag.
        span.set_metric(
          Ext::DistributedTracing::SAMPLING_PRIORITY_KEY,
          priority
        )
      end
    end
  end
end
