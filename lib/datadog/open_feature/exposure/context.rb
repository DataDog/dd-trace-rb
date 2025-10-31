module Datadog
  module OpenFeature
    module Exposure
      module Context
        module_function

        def build(service: nil, env: nil, version: nil, geo: nil)
          config = Datadog.configuration
          context = {}
          context[:service] = service || config.service if present?(service || config.service)
          context[:env] = env || config.env if present?(env || config.env)
          context[:version] = version || config.version if present?(version || config.version)
          if geo.is_a?(Hash)
            geo_data = geo.select { |key, _| %i[country_iso_code country].include?(key) }
            context[:geo] = geo_data if geo_data.any?
          end
          context
        end

        def present?(value)
          !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
        end
        private_class_method :present?
      end
    end
  end
end
