# typed: true
require 'forwardable'

require 'ddtrace/ext/priority'
require 'ddtrace/ext/sampling'
require 'ddtrace/diagnostics/health'

module Datadog
  # Interface for client-side trace sampling.
  # @abstract
  class Sampler
    # Returns `true` if the provided span should be kept as part of the trace.
    # Otherwise, `false`.
    #
    # This method *must not* modify the `span`.
    #
    # @param [Datadog::Span] span
    # @return [Boolean] should this span be kept?
    # TODO: will this receive span, tracer or both
    def sample?(span)
      raise NotImplementedError, 'Samplers must implement the #sample? method'
    end

    # Returns `true` if the provided span should be kept as part of the trace.
    # Otherwise, `false`.
    #
    # This method *may* modify the `span`, in case changes are necessary based on the
    # sampling decision.
    #
    # @param [Datadog::Span] span
    # @return [Boolean] should this span be kept?
    # TODO: will this receive span, tracer or both
    def sample!(span)
      raise NotImplementedError, 'Samplers must implement the #sample! method'
    end

    # The sampling rate, if this sampler has such concept.
    # Otherwise, `nil`.
    #
    # @param [Datadog::Span] span
    # @return [Float,nil] sampling ratio between 0.0 and 1.0 (inclusive), or `nil` if not applicable
    # TODO: will this receive span, tracer or both
    def sample_rate(span)
      raise NotImplementedError, 'Samplers must implement the #sample_rate method'
    end
  end

  # \AllSampler samples all the traces.
  class AllSampler < Sampler
    def sample?(_trace)
      true
    end

    def sample!(trace)
      trace.sampled = true
    end

    def sample_rate(*_)
      1.0
    end
  end

  # \RateSampler is based on a sample rate.
  class RateSampler < Sampler
    KNUTH_FACTOR = 1111111111111111111

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

    def sample?(trace)
      ((trace.id * KNUTH_FACTOR) % Datadog::Span::EXTERNAL_MAX_ID) <= @sampling_id_threshold
    end

    def sample!(trace)
      sampled = trace.sampled = sample?(trace)
      trace.sample_rate = @sample_rate if sampled
      sampled
    end
  end

  # Samples at different rates by key.
  class RateByKeySampler < Sampler
    attr_reader \
      :default_key

    def initialize(default_key, default_rate = 1.0, &block)
      raise ArgumentError, 'No resolver given!' unless block

      @default_key = default_key
      @resolver = block
      @mutex = Mutex.new
      @samplers = {}

      set_rate(default_key, default_rate)
    end

    def resolve(trace)
      @resolver.call(trace)
    end

    def default_sampler
      @samplers[default_key]
    end

    def sample?(trace)
      key = resolve(trace)

      @mutex.synchronize do
        @samplers.fetch(key, default_sampler).sample?(trace)
      end
    end

    def sample!(trace)
      key = resolve(trace)

      @mutex.synchronize do
        @samplers.fetch(key, default_sampler).sample!(trace)
      end
    end

    def sample_rate(trace)
      key = resolve(trace)

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

    def key_for(trace)
      # Resolve env dynamically, if Proc is given.
      env = @env.is_a?(Proc) ? @env.call : @env

      "service:#{trace.service},env:#{env}"
    end
  end

  # \PrioritySampler
  class PrioritySampler
    extend Forwardable

    # NOTE: We do not advise using a pre-sampler. It can save resources,
    # but pre-sampling at rates < 100% may result in partial traces, unless
    # the pre-sampler knows exactly how to drop a span without dropping its ancestors.
    #
    # Additionally, as service metrics are calculated in the Datadog Agent,
    # the service's throughput will be underestimated.
    attr_reader :pre_sampler, :priority_sampler

    def initialize(opts = {})
      @pre_sampler = opts[:base_sampler] || AllSampler.new
      @priority_sampler = opts[:post_sampler] || RateByServiceSampler.new
    end

    def sample?(trace)
      @pre_sampler.sample?(trace)
    end

    def sample!(trace)
      # If pre-sampling is configured, do it first. (By default, this will sample at 100%.)
      # NOTE: Pre-sampling at rates < 100% may result in partial traces; not recommended.
      trace.sampled = pre_sample?(trace) ? @pre_sampler.sample!(trace) : true

      if trace.sampled?
        # If priority sampling has already been applied upstream, use that value.
        return true if priority_assigned?(trace)

        # Check with post sampler how we set the priority.
        sample = priority_sample!(trace)

        # Check if post sampler has already assigned a priority.
        return true if priority_assigned?(trace)

        # If not, use agent priority values.
        priority = sample ? Datadog::Ext::Priority::AUTO_KEEP : Datadog::Ext::Priority::AUTO_REJECT
        assign_priority!(trace, priority)
      else
        # If discarded by pre-sampling, set "reject" priority, so other
        # services for the same trace don't sample needlessly.
        assign_priority!(trace, Datadog::Ext::Priority::AUTO_REJECT)
      end

      trace.sampled?
    end

    def_delegators :@priority_sampler, :update

    private

    def pre_sample?(trace)
      case @pre_sampler
      when RateSampler
        @pre_sampler.sample_rate < 1.0
      when RateByServiceSampler
        @pre_sampler.sample_rate(trace) < 1.0
      else
        true
      end
    end

    def priority_assigned?(trace)
      !trace.sampling_priority.nil?
    end

    def priority_sample!(trace)
      preserving_sampling(trace) do
        @priority_sampler.sample!(trace)
      end
    end

    # Ensures the trace is always propagated to the writer and that
    # the sample rate metric represents the true client-side sampling.
    def preserving_sampling(trace)
      pre_sample_rate_metric = trace.sample_rate

      yield.tap do
        # NOTE: We'll want to leave `trace.sampled = true` here; all spans for priority sampling must
        #       be sent to the agent. Otherwise metrics for traces will not be accurate, since the
        #       agent will have an incomplete dataset.
        #
        #       We also ensure that the agent knows we that our `post_sampler` is not performing true sampling,
        #       to avoid erroneous metric upscaling.
        trace.sampled = true

        # Restore true sampling metric, as only the @pre_sampler can reject traces.
        # otherwise if @pre_sampler is not enabled, sending this metric would be misleading.
        trace.sample_rate = pre_sample_rate_metric || nil
      end
    end

    def assign_priority!(trace, priority)
      trace.sampling_priority = priority
    end
  end
end
