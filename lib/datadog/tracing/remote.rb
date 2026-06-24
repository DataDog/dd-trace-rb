# frozen_string_literal: true

require_relative '../core/remote/dispatcher'
require_relative 'configuration/dynamic'

module Datadog
  module Tracing
    # Remote configuration declaration
    module Remote
      class << self
        PRODUCT = 'APM_TRACING'

        CAPABILITIES = [
          1 << 12, # APM_TRACING_SAMPLE_RATE: Dynamic trace sampling rate configuration
          1 << 13, # APM_TRACING_LOGS_INJECTION: Dynamic trace logs injection configuration
          1 << 14, # APM_TRACING_HTTP_HEADER_TAGS: Dynamic trace HTTP header tags configuration
          1 << 29, # APM_TRACING_SAMPLE_RULES: Dynamic trace sampling rules configuration
          # APM_TRACING_ENABLE_DYNAMIC_INSTRUMENTATION (bit 38) is declared in
          # DI::Remote.capabilities, not here, so it is registered only when DI
          # is not explicitly disabled. The enable signal is still delivered in
          # APM_TRACING payloads and routed by process_config below.
        ].freeze

        def products
          [PRODUCT]
        end

        def capabilities
          CAPABILITIES
        end

        def process_config(config, content, repository = nil)
          lib_config = config['lib_config']

          env_vars = Datadog::Tracing::Configuration::Dynamic::OPTIONS.map do |name, env_var, option|
            value = lib_config[name]

            # Guard for RBS/Steep
            raise "option is a #{option.class}, expected Option" unless option.is_a?(Configuration::Dynamic::Option)

            option.call(value)

            [env_var, value]
          end

          if (di_enabled = lib_config['dynamic_instrumentation_enabled']) != nil # rubocop:disable Style/NonNilCheck
            # repository is forwarded so that an enable signal can reconcile DI
            # against probes delivered in an earlier poll while DI was stopped
            # (see Datadog::DI::Remote.handle_rc_enablement).
            Datadog::DI::Remote.handle_rc_enablement(di_enabled, repository)
          end

          content.applied

          # allow_initialization: false because process_config runs on the
          # remote-config worker thread. If components haven't been built yet
          # (e.g. during a teardown/reset window), the default `true` would
          # synchronously build the entire component tree from this thread.
          # The &. chain matches the pattern used by DI::Remote.handle_rc_enablement
          # in the same dispatch path.
          Datadog.send(:components, allow_initialization: false)&.telemetry&.client_configuration_change!(env_vars)
        rescue => e
          content.errored("#{e.class}: #{e.message}: #{Array(e.backtrace).join("\n")}")
        end

        def receivers(_telemetry)
          receiver do |repository, _changes|
            # DEV: Filter our by product. Given it will be very common
            # DEV: we can filter this out before we receive the data in this method.
            # DEV: Apply this refactor to AppSec as well if implemented.
            repository.contents.map do |content|
              case content.path.product
              when PRODUCT
                config = parse_content(content)
                process_config(config, content, repository)
              end
            end
          end
        end

        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
        end

        private

        def parse_content(content)
          JSON.parse(content.data)
        end
      end
    end
  end
end
