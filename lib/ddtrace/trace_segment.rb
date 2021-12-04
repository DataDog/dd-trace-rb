require 'forwardable'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/priority'
require 'ddtrace/ext/sampling'

module Datadog
  # Serializable construct representing a trace
  # @public_api
  class TraceSegment
    extend Forwardable

    TAG_NAME = 'name'.freeze
    TAG_RESOURCE = 'resource'.freeze
    TAG_SERVICE = 'service'.freeze

    SPANS_METHODS = [
      :any?,
      :count,
      :empty?,
      :length,
      :size
    ].freeze

    attr_reader \
      :id,
      :spans,
      :tags

    def initialize(
      spans,
      agent_sample_rate: nil,
      hostname: nil,
      id: nil,
      lang: nil,
      name: nil,
      origin: nil,
      process_id: nil,
      rate_limiter_rate: nil,
      resource: nil,
      root_span_id: nil,
      rule_sample_rate: nil,
      runtime_id: nil,
      sample_rate: nil,
      sampling_priority: nil,
      service: nil
    )
      @id = id
      @root_span_id = root_span_id
      @spans = spans || []
      @tags = {}

      # Set well-known tags
      self.agent_sample_rate = agent_sample_rate
      self.hostname = (hostname && hostname.dup)
      self.lang = (lang && lang.dup)
      self.name = (name && name.dup)
      self.origin = (origin && origin.dup)
      self.process_id = process_id
      self.rate_limiter_rate = rate_limiter_rate
      self.resource = (resource && resource.dup)
      self.rule_sample_rate = rule_sample_rate
      self.runtime_id = (runtime_id && runtime_id.dup)
      self.sample_rate = sample_rate
      self.sampling_priority = sampling_priority
      self.service = (service && service.dup)
    end

    def_delegators :spans, *SPANS_METHODS

    # Define tag accessors
    {
      agent_sample_rate: Ext::Sampling::TAG_AGENT_RATE,
      hostname: Ext::NET::TAG_HOSTNAME,
      lang: Ext::Runtime::TAG_LANG,
      name: TAG_NAME,
      origin: Ext::DistributedTracing::TAG_ORIGIN,
      process_id: Ext::Runtime::TAG_PID,
      rate_limiter_rate: Ext::Sampling::TAG_RATE_LIMITER_RATE,
      resource: TAG_RESOURCE,
      rule_sample_rate: Ext::Sampling::TAG_RULE_SAMPLE_RATE,
      runtime_id: Ext::Runtime::TAG_ID,
      sample_rate: Ext::Sampling::TAG_SAMPLE_RATE,
      sampling_priority: Ext::DistributedTracing::TAG_SAMPLING_PRIORITY,
      service: TAG_SERVICE
    }.each do |tag_name, tag_key|
      define_method(tag_name) { tags[tag_key] }
      define_method(:"#{tag_name}=") do |value|
        value.nil? ? tags.delete(value) : tags[tag_key] = value
      end
    end

    # If an active trace is present, forces it to be retained by the Datadog backend.
    #
    # Any sampling logic will not be able to change this decision.
    #
    # @return [void]
    def keep!
      self.sampling_priority = Datadog::Ext::Priority::USER_KEEP
    end

    # If an active trace is present, forces it to be dropped and not stored by the Datadog backend.
    #
    # Any sampling logic will not be able to change this decision.
    #
    # @return [void]
    def reject!
      self.sampling_priority = Datadog::Ext::Priority::USER_REJECT
    end

    def sampled?
      sampling_priority == Datadog::Ext::Priority::AUTO_KEEP \
        || sampling_priority == Datadog::Ext::Priority::USER_KEEP
    end

    protected

    attr_reader \
      :root_span_id
  end
end
