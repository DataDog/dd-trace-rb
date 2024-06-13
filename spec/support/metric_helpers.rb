require 'support/statsd_helpers'

module MetricHelpers
  include RSpec::Mocks::ArgumentMatchers

  shared_context 'metrics' do
    include_context 'statsd'

    def metric_options(options = nil)
      return options unless options.nil? || options.is_a?(Hash)

      Datadog::Core::Metrics::Client.metric_options(options)
    end

    def check_options!(options)
      if options.is_a?(Hash)
        expect(options.frozen?).to be false
        expect(options[:tags].frozen?).to be false if options.key?(:tags)
      end
    end

    # Define matchers for use in examples
    def have_received_count_metric(stat, value = kind_of(Numeric), options = {})
      options = metric_options(options)
      check_options!(options)
      have_received(:count).with(stat, value, options)
    end

    def have_received_distribution_metric(stat, value = kind_of(Numeric), options = {})
      options = metric_options(options)
      check_options!(options)
      have_received(:distribution).with(stat, value, options)
    end

    def have_received_gauge_metric(stat, value = kind_of(Numeric), options = {})
      options = metric_options(options)
      check_options!(options)
      have_received(:gauge).with(stat, value, options)
    end

    def have_received_increment_metric(stat, options = {})
      options = metric_options(options)
      check_options!(options)
      have_received(:increment).with(stat, options)
    end

    def have_received_time_metric(stat, options = {})
      options = metric_options(options)
      check_options!(options)
      have_received(:distribution).with(stat, kind_of(Numeric), options)
    end
  end
end
