# frozen_string_literal: true

module Datadog
  module Core
    module Metrics
      # For defining and adding helpers to metrics
      module Helpers
        [
          :count,
          :distribution,
          :increment,
          :gauge,
          :time,
        ].each do |metric_type|
          # Steep ignores @type self annotations inside define_method blocks,
          # so the Module-receiver call and the instance send carry scoped
          # ignores. The hosts are Modules (Client extends this module) and
          # respond to the metric methods being generated.
          define_method(metric_type) do |name, stat|
            name = name.to_sym
            define_method(name) do |*args, &block| # steep:ignore NoMethod
              send(metric_type, stat, *args, &block) # steep:ignore NoMethod
            end
          end
        end
      end
    end
  end
end
