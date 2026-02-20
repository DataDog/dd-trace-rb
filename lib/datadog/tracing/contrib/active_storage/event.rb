# frozen_string_literal: true

require_relative '../active_support/notifications/event'
require_relative '../analytics'
require_relative '../../metadata/ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # Defines basic behaviors for an ActiveStorage event.
        module Event
          def self.included(base)
            base.include(ActiveSupport::Notifications::Event)
            base.extend(ClassMethods)
          end

          # Class methods for ActiveStorage events.
          module ClassMethods
            def span_options
              if configuration[:service_name]
                { service: configuration[:service_name] }
              else
                {}
              end
            end

            def configuration
              Datadog.configuration.tracing[:active_storage]
            end

            # Set analytics sample rate on span if enabled
            def set_analytics(span)
              return unless Contrib::Analytics.enabled?(configuration[:analytics_enabled])

              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Set component and operation tags on span
            def set_tags(span, operation_tag)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, operation_tag)
            end
          end
        end
      end
    end
  end
end
