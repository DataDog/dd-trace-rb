# typed: true
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/active_support/notifications/event'
require 'datadog/tracing/contrib/active_model_serializers/ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveModelSerializers
        # Defines basic behaviors for an ActiveModelSerializers event.
        module Event
          def self.included(base)
            base.include(ActiveSupport::Notifications::Event)
            base.extend(ClassMethods)
          end

          # Class methods for ActiveModelSerializers events.
          # Note, they share the same process method and before_trace method.
          module ClassMethods
            def span_options
              {}
            end

            def configuration
              Tracing.configuration[:active_model_serializers]
            end

            def set_common_tags(span, payload)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              # Set the resource name and serializer name
              res = resource(payload[:serializer])
              span.resource = res
              span.set_tag(Ext::TAG_SERIALIZER, res)

              span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE

              # Will be nil in 0.9
              span.set_tag(Ext::TAG_ADAPTER, payload[:adapter].class) unless payload[:adapter].nil?
            end

            private

            def resource(serializer)
              # Depending on the version of ActiveModelSerializers
              # serializer will be a string or an object.
              if serializer.respond_to?(:name)
                serializer.name
              else
                serializer
              end
            end
          end
        end
      end
    end
  end
end
