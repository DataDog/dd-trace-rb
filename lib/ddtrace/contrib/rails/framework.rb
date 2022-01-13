# typed: false
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
require 'ddtrace/contrib/action_cable/integration'
require 'ddtrace/contrib/action_mailer/integration'
require 'ddtrace/contrib/action_pack/integration'
require 'ddtrace/contrib/action_view/integration'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/lograge/integration'
require 'ddtrace/contrib/semantic_logger/integration'

require 'ddtrace/contrib/rails/ext'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails framework code, used to essentially:
      # - handle configuration entries which are specific to Datadog tracing
      # - instrument parts of the framework when needed
      module Framework
        # After the Rails application finishes initializing, we configure the Rails
        # integration and all its sub-components with the application information
        # available.
        # We do this after the initialization because not all the information we
        # require is available before then.
        def self.setup
          # NOTE: #configure has the side effect of rebuilding trace components.
          #       During a typical Rails application lifecycle, we will see trace
          #       components initialized twice because of this. This is necessary
          #       because key configuration is not available until after the Rails
          #       application has fully loaded, and some of this configuration is
          #       used to reconfigure tracer components with Rails-sourced defaults.
          #       This is a trade-off we take to get nice defaults.
          Datadog.configure do |datadog_config|
            # By default, default service would be guessed from the script
            # being executed, but here we know better, get it from Rails config.
            # Don't set this if service has been explicitly provided by the user.
            rails_service_name =  Datadog::Tracing.configuration[:rails][:service_name] \
                                    || Datadog.configuration.service_without_fallback \
                                    || Utils.app_name

            datadog_config.service ||= rails_service_name
          end

          Datadog::Tracing.configure do |trace_config|
            rails_config = trace_config[:rails]

            activate_rack!(trace_config, rails_config)
            activate_action_cable!(trace_config, rails_config)
            activate_action_mailer!(trace_config, rails_config)
            activate_active_support!(trace_config, rails_config)
            activate_action_pack!(trace_config, rails_config)
            activate_action_view!(trace_config, rails_config)
            activate_active_job!(trace_config, rails_config)
            activate_active_record!(trace_config, rails_config)
            activate_lograge!(trace_config, rails_config)
            activate_semantic_logger!(trace_config, rails_config)
          end
        end

        def self.activate_rack!(trace_config, rails_config)
          trace_config.use(
            :rack,
            application: ::Rails.application,
            service_name: rails_config[:service_name],
            middleware_names: rails_config[:middleware_names],
            distributed_tracing: rails_config[:distributed_tracing]
          )
        end

        def self.activate_active_support!(trace_config, rails_config)
          return unless defined?(::ActiveSupport)

          trace_config.use(:active_support)
        end

        def self.activate_action_cable!(trace_config, rails_config)
          return unless defined?(::ActionCable)

          trace_config.use(:action_cable)
        end

        def self.activate_action_mailer!(trace_config, rails_config)
          return unless defined?(::ActionMailer)

          trace_config.use(
            :action_mailer,
            service_name: rails_config[:service_name]
          )
        end

        def self.activate_action_pack!(trace_config, rails_config)
          return unless defined?(::ActionPack)

          trace_config.use(
            :action_pack,
            service_name: rails_config[:service_name]
          )
        end

        def self.activate_action_view!(trace_config, rails_config)
          return unless defined?(::ActionView)

          trace_config.use(
            :action_view,
            service_name: rails_config[:service_name]
          )
        end

        def self.activate_active_job!(trace_config, rails_config)
          return unless defined?(::ActiveJob)

          # Check before passing :log_injection to the Rails configuration
          # to avoid triggering a deprecated setting warning when the user
          # didn't actually provide an explicit `c.use rails, :log_injection`.
          deprecated_options = {}
          deprecated_options[:log_injection] = rails_config[:log_injection] unless rails_config[:log_injection].nil?

          trace_config.use(
            :active_job,
            service_name: rails_config[:service_name],
            **deprecated_options
          )
        end

        def self.activate_active_record!(trace_config, rails_config)
          return unless defined?(::ActiveRecord)

          trace_config.use(:active_record)
        end

        def self.activate_lograge!(trace_config, rails_config)
          return unless defined?(::Lograge)

          if rails_config[:log_injection]
            trace_config.use(
              :lograge
            )
          end
        end

        def self.activate_semantic_logger!(trace_config, rails_config)
          return unless defined?(::SemanticLogger)

          if rails_config[:log_injection]
            trace_config.use(
              :semantic_logger
            )
          end
        end
      end
    end
  end
end
