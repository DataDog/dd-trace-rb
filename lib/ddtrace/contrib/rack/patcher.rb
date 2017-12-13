module Datadog
  module Contrib
    module Rack
      module Patcher
        include Base
        register_as :rack

        option :tracer, default: Datadog.tracer
        option :distributed_tracing, default: false
        option :service_name, default: 'rack', depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'rack', Ext::AppTypes::WEB)
          value
        end

        def self.patch
          require_relative 'middlewares'
        end
      end
    end
  end
end
