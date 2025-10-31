module Datadog
  module OpenFeature
    module Exposure
      class Batch
        attr_reader :context, :exposures

        def initialize(context:, exposures: [])
          @context = context
          @exposures = Array(exposures)
        end

        def add(event)
          exposures << event
        end

        def empty?
          exposures.empty?
        end

        def to_h
          hash = { exposures: serialized_exposures }
          context_hash = sanitize_context(context)
          hash[:context] = context_hash if context_hash.any?
          hash
        end

        private

        def sanitize_context(raw_context)
          return {} unless raw_context.is_a?(Hash)

          raw_context.each_with_object({}) do |(key, value), result|
            next unless %i[service env version geo].include?(key)

            if key == :geo
              next unless value.is_a?(Hash)

              geo_value = value.each_with_object({}) do |(geo_key, geo_val), geo_hash|
                next unless %i[country_iso_code country].include?(geo_key)

                geo_hash[geo_key] = geo_val
              end
              result[key] = geo_value if geo_value.any?
            else
              next if value.nil?

              result[key] = value
            end
          end
        end

        def serialized_exposures
          exposures.map do |event|
            event.respond_to?(:to_h) ? event.to_h : event
          end
        end
      end
    end
  end
end
