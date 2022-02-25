# typed: false

require 'datadog/tracing'
require 'datadog/tracing/contrib/action_cable/integration'
require 'datadog/tracing/contrib/action_mailer/integration'
require 'datadog/tracing/contrib/action_pack/integration'
require 'datadog/tracing/contrib/action_view/integration'
require 'datadog/tracing/contrib/active_record/integration'
require 'datadog/tracing/contrib/active_support/integration'
require 'datadog/tracing/contrib/grape/endpoint'
require 'datadog/tracing/contrib/lograge/integration'
require 'datadog/tracing/contrib/rails/ext'
require 'datadog/tracing/contrib/rails/utils'
require 'datadog/tracing/contrib/semantic_logger/integration'

module Datadog
  module Tracing
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
              rails_service_name = Datadog.configuration[:rails][:service_name] \
                                    || Datadog.configuration.service_without_fallback \
                                    || Utils.app_name

              datadog_config.service ||= rails_service_name
            end

            Datadog.configure do |trace_config|
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
            trace_config.tracing.instrument(
              :rack,
              application: ::Rails.application,
              service_name: rails_config[:service_name],
              middleware_names: rails_config[:middleware_names],
              distributed_tracing: rails_config[:distributed_tracing]
            )
          end

          def self.activate_active_support!(trace_config, rails_config)
            return unless defined?(::ActiveSupport)

            trace_config.tracing.instrument(:active_support)
          end

          def self.activate_action_cable!(trace_config, rails_config)
            return unless defined?(::ActionCable)

            trace_config.tracing.instrument(:action_cable)
          end

          def self.activate_action_mailer!(trace_config, rails_config)
            return unless defined?(::ActionMailer)

            trace_config.tracing.instrument(
              :action_mailer,
              service_name: rails_config[:service_name]
            )
          end

          def self.activate_action_pack!(trace_config, rails_config)
            return unless defined?(::ActionPack)

            trace_config.tracing.instrument(
              :action_pack,
              service_name: rails_config[:service_name]
            )
          end

          def self.activate_action_view!(trace_config, rails_config)
            return unless defined?(::ActionView)

            trace_config.tracing.instrument(
              :action_view,
              service_name: rails_config[:service_name]
            )
          end

          def self.activate_active_job!(trace_config, rails_config)
            return unless defined?(::ActiveJob)

            trace_config.tracing.instrument(
              :active_job,
              service_name: rails_config[:service_name]
            )
          end

          def self.activate_active_record!(trace_config, rails_config)
            return unless defined?(::ActiveRecord)

            trace_config.tracing.instrument(:active_record)
          end

          def self.activate_lograge!(trace_config, rails_config)
            return unless defined?(::Lograge)

            if trace_config.tracing.log_injection
              trace_config.tracing.instrument(
                :lograge
              )
            end
          end

          def self.activate_semantic_logger!(trace_config, rails_config)
            return unless defined?(::SemanticLogger)

            if trace_config.tracing.log_injection
              trace_config.tracing.instrument(
                :semantic_logger
              )
            end
          end
        end
      end
    end
  end
end
