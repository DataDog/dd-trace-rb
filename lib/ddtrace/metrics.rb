require 'ddtrace/ext/metrics'

require 'set'
require 'logger'
require 'ddtrace/environment'
require 'ddtrace/utils/time'
require 'ddtrace/runtime/identity'

module Datadog
  # Acts as client for sending metrics (via Statsd)
  # Wraps a Statsd client with default tags and additional configuration.
  class Metrics
    attr_reader :statsd

    def initialize(options = {})
      @statsd = options.fetch(:statsd) { default_statsd_client if supported? }
      @enabled = options.fetch(:enabled, true)
    end

    def supported?
      version = (
          defined?(Datadog::Statsd::VERSION) &&
          Datadog::Statsd::VERSION &&
          Gem::Version.new(Datadog::Statsd::VERSION)
        ) || (
          Gem.loaded_specs['dogstatsd-ruby'] &&
          Gem.loaded_specs['dogstatsd-ruby'].version
        )

      !version.nil? && (version >= Gem::Version.new('3.3.0'))
    end

    def enabled?
      @enabled
    end

    def enabled=(enabled)
      @enabled = (enabled == true)
    end

    def default_hostname
      ENV.fetch(Datadog::Ext::Metrics::ENV_DEFAULT_HOST, Datadog::Ext::Metrics::DEFAULT_HOST)
    end

    def default_port
      ENV.fetch(Datadog::Ext::Metrics::ENV_DEFAULT_PORT, Datadog::Ext::Metrics::DEFAULT_PORT).to_i
    end

    def default_statsd_client
      require 'datadog/statsd'

      # Create a StatsD client that points to the agent.
      Datadog::Statsd.new(default_hostname, default_port)
    end

    def configure(options = {})
      @statsd = options[:statsd] if options.key?(:statsd)
      self.enabled = options[:enabled] if options.key?(:enabled)
    end

    def send_stats?
      enabled? && !statsd.nil?
    end

    def count(stat, value = nil, options = nil, &block)
      return unless send_stats? && statsd.respond_to?(:count)

      value, options = yield if block
      raise ArgumentError if value.nil?

      statsd.count(stat, value, metric_options(options))
    rescue StandardError => e
      Datadog.logger.error("Failed to send count stat. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def distribution(stat, value = nil, options = nil, &block)
      return unless send_stats? && statsd.respond_to?(:distribution)

      value, options = yield if block
      raise ArgumentError if value.nil?

      statsd.distribution(stat, value, metric_options(options))
    rescue StandardError => e
      Datadog.logger.error("Failed to send distribution stat. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def increment(stat, options = nil)
      return unless send_stats? && statsd.respond_to?(:increment)

      options = yield if block_given?

      statsd.increment(stat, metric_options(options))
    rescue StandardError => e
      Datadog.logger.error("Failed to send increment stat. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def gauge(stat, value = nil, options = nil, &block)
      return unless send_stats? && statsd.respond_to?(:gauge)

      value, options = yield if block
      raise ArgumentError if value.nil?

      statsd.gauge(stat, value, metric_options(options))
    rescue StandardError => e
      Datadog.logger.error("Failed to send gauge stat. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def time(stat, options = nil)
      return yield unless send_stats?

      # Calculate time, send it as a distribution.
      start = Utils::Time.get_time
      yield
    ensure
      begin
        if send_stats? && !start.nil?
          finished = Utils::Time.get_time
          distribution(stat, ((finished - start) * 1000), options)
        end
      rescue StandardError => e
        Datadog.logger.error("Failed to send time stat. Cause: #{e.message} Source: #{e.backtrace.first}")
      end
    end

    def send_metrics(metrics)
      metrics.each { |m| send(m.type, *[m.name, m.value, m.options].compact) }
    end

    def close
      @statsd.close if @statsd && @statsd.respond_to?(:close)
    end

    Metric = Struct.new(:type, :name, :value, :options) do
      def initialize(*args)
        super
        self.options = options || {}
      end
    end

    # For defining and adding default options to metrics
    module Options
      DEFAULT = {
        tags: DEFAULT_TAGS = [
          "#{Ext::Metrics::TAG_LANG}:#{Runtime::Identity.lang}".freeze,
          "#{Ext::Metrics::TAG_LANG_INTERPRETER}:#{Runtime::Identity.lang_interpreter}".freeze,
          "#{Ext::Metrics::TAG_LANG_VERSION}:#{Runtime::Identity.lang_version}".freeze,
          "#{Ext::Metrics::TAG_TRACER_VERSION}:#{Runtime::Identity.tracer_version}".freeze
        ].freeze
      }.freeze

      def metric_options(options = nil)
        return default_metric_options if options.nil?

        default_metric_options.merge(options) do |key, old_value, new_value|
          case key
          when :tags
            old_value.dup.concat(new_value).uniq
          else
            new_value
          end
        end
      end

      def default_metric_options
        # Return dupes, so that the constant isn't modified,
        # and defaults are unfrozen for mutation in Statsd.
        DEFAULT.dup.tap do |options|
          options[:tags] = options[:tags].dup

          env = Datadog.configuration.env
          options[:tags] << "#{Datadog::Ext::Environment::TAG_ENV}:#{env}" unless env.nil?

          version = Datadog.configuration.version
          options[:tags] << "#{Datadog::Ext::Environment::TAG_VERSION}:#{version}" unless version.nil?
        end
      end
    end

    # For defining and adding helpers to metrics
    module Helpers
      [
        :count,
        :distribution,
        :increment,
        :gauge,
        :time
      ].each do |metric_type|
        define_method(metric_type) do |name, stat|
          name = name.to_sym
          define_method(name) do |*args, &block|
            send(metric_type, stat, *args, &block)
          end
        end
      end
    end

    module Logging
      # Surrogate for Datadog::Statsd to log elsewhere
      class Adapter
        attr_accessor :logger

        def initialize(logger = nil)
          @logger = logger || Logger.new($stdout).tap do |l|
            l.level = Logger::INFO
            l.progname = nil
            l.formatter = proc do |_severity, datetime, _progname, msg|
              stat = JSON.parse(msg[3..-1]) # Trim off leading progname...
              "#{JSON.dump(timestamp: datetime.to_i, message: 'Metric sent.', metric: stat)}\n"
            end
          end
        end

        def count(stat, value, options = nil)
          logger.info({ stat: stat, type: :count, value: value, options: options }.to_json)
        end

        def distribution(stat, value, options = nil)
          logger.info({ stat: stat, type: :distribution, value: value, options: options }.to_json)
        end

        def increment(stat, options = nil)
          logger.info({ stat: stat, type: :increment, options: options }.to_json)
        end

        def gauge(stat, value, options = nil)
          logger.info({ stat: stat, type: :gauge, value: value, options: options }.to_json)
        end
      end
    end

    # Make available on for both class and instance.
    include Options
    extend Options
    extend Helpers
  end
end
