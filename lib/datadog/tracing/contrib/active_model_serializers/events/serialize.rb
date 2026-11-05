# frozen_string_literal: true

require_relative "../ext"
require_relative "../event"

module Datadog
  module Tracing
    module Contrib
      module ActiveModelSerializers
        module Events
          # Defines instrumentation for !serialize.active_model_serializers event
          module Serialize
            include ActiveModelSerializers::Event

            EVENT_NAME = "!serialize.active_model_serializers"

            def self.supported?
              Gem.loaded_specs["active_model_serializers"] \
                &&
                Gem.loaded_specs["active_model_serializers"].version >= Gem::Version.new("0.9") \
                  && Gem.loaded_specs["active_model_serializers"].version < Gem::Version.new("0.10")
            end

            def self.event_name
              self::EVENT_NAME
            end

            def self.span_name
              Ext::SPAN_SERIALIZE
            end

            def self.on_start(span, _event, _id, payload)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_SERIALIZE)

              set_common_tags(span, payload)
            rescue => e
              Datadog.logger.debug { "#{e.class}: #{e.message}" }
            end
          end
        end
      end
    end
  end
end
