require 'support/statsd_helpers'

module MetricHelpers
  include RSpec::Mocks::ArgumentMatchers

  shared_context 'metrics' do
    include_context 'statsd'

    # Define default options and tags
    def metric_options(options = nil)
      return Datadog::Metrics::DEFAULT_OPTIONS.dup if options.nil?
      return options unless options.is_a?(Hash)
      options.merge(tags: metric_tags_with(options[:tags]))
    end

    def metric_tags_with(tags)
      metric_tags.tap do |default_tags|
        default_tags.concat(tags) unless tags.nil?
      end
    end

    def metric_tags
      Datadog::Metrics::DEFAULT_TAGS.dup
    end

    # Define matchers for use in examples
    def have_received_distribution_metric(stat, value = kind_of(Numeric), options = {})
      have_received(:distribution).with(stat, value, metric_options(options))
    end

    def have_received_increment_metric(stat, options = {})
      have_received(:increment).with(stat, metric_options(options))
    end

    def have_received_time_metric(stat, options = {})
      have_received(:distribution).with(stat, kind_of(Numeric), metric_options(options))
    end

    # Define shared examples
    shared_examples_for 'an operation that sends distribution metric' do |stat, options = {}|
      let(:value) { kind_of(Numeric) }

      it do
        subject
        expect(statsd).to have_received_distribution_metric(stat, value, options)
      end
    end

    shared_examples_for 'an operation that sends increment metric' do |stat, options = {}|
      it do
        subject
        expect(statsd).to have_received_increment_metric(stat, options)
      end
    end

    shared_examples_for 'an operation that sends time metric' do |stat, options = {}|
      it do
        subject
        expect(statsd).to have_received_time_metric(stat, options)
      end
    end
  end

  shared_context 'transport metrics' do
    include_context 'metrics'

    # Define default options and tags
    def transport_options(options = {}, encoder = Datadog::Encoding::MsgpackEncoder)
      return options unless options.is_a?(Hash)
      { tags: transport_tags_with(options[:tags], encoder) }
    end

    def transport_tags_with(tags, encoder = Datadog::Encoding::MsgpackEncoder)
      transport_tags(encoder).tap do |default_tags|
        default_tags.concat(tags) unless tags.nil?
      end
    end

    def transport_tags(encoder = Datadog::Encoding::MsgpackEncoder)
      ["#{Datadog::Ext::Metrics::TAG_ENCODING_TYPE}:#{encoder.content_type}"]
    end

    # Define matchers for use in examples
    def have_received_distribution_transport_metric(
      stat,
      value = kind_of(Numeric),
      options = {},
      encoder = Datadog::Encoding::MsgpackEncoder
    )
      have_received_distribution_metric(stat, value, transport_options(options, encoder))
    end

    def have_received_increment_transport_metric(stat, options = {}, encoder = Datadog::Encoding::MsgpackEncoder)
      have_received_increment_metric(stat, transport_options(options, encoder))
    end

    def have_received_time_transport_metric(stat, options = {}, encoder = Datadog::Encoding::MsgpackEncoder)
      have_received_time_metric(stat, transport_options(options, encoder))
    end

    # Define shared examples
    shared_examples_for 'a transport operation that sends distribution metric' do |stat, options = {}|
      let(:value) { kind_of(Numeric) }
      let(:encoder) { Datadog::Encoding::MsgpackEncoder }

      it do
        subject
        expect(statsd).to have_received_distribution_transport_metric(stat, value, options, encoder)
      end
    end

    shared_examples_for 'a transport operation that sends increment metric' do |stat, options = {}|
      let(:encoder) { Datadog::Encoding::MsgpackEncoder }

      it do
        subject
        expect(statsd).to have_received_increment_transport_metric(stat, options, encoder)
      end
    end

    shared_examples_for 'a transport operation that sends time metric' do |stat, options = {}|
      let(:encoder) { Datadog::Encoding::MsgpackEncoder }

      it do
        subject
        expect(statsd).to have_received_time_transport_metric(stat, options, encoder)
      end
    end
  end
end
