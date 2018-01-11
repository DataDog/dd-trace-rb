module Datadog
  module Contrib
    module Rack
      # Provides instrumentation for `rack`
      module Patcher
        include Base
        register_as :rack
        option :tracer, default: Datadog.tracer
        option :distributed_tracing, default: false
        option :middleware_names, default: false
        option :application
        option :service_name, default: 'rack', depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'rack', Ext::AppTypes::WEB)
          value
        end

        module_function

        def patch
          return true if patched?

          require_relative 'middlewares'
          @patched = true

          enable_middleware_names if get_option(:middleware_names)
        end

        def patched?
          @patched ||= false
        end

        def enable_middleware_names
          root = get_option(:application) || rails_app
          retain_middleware_name(root)
        rescue => e
          # We can safely ignore these exceptions since they happen only in the
          # context of middleware patching outside a Rails server process (eg. a
          # process that doesn't serve HTTP requests but has Rails environment
          # loaded such as a Resque master process)
          Tracer.log.debug("Error patching middleware stack: #{e}")
        end

        def rails_app
          return unless Datadog.registry[:rails].compatible?
          ::Rails.application.app
        end

        def retain_middleware_name(middleware)
          return unless middleware && middleware.respond_to?(:call)

          middleware.singleton_class.class_eval do
            alias_method :__call, :call

            def call(env)
              env['RESPONSE_MIDDLEWARE'] = self.class.to_s
              __call(env)
            end
          end

          following = middleware.instance_variable_get('@app')
          retain_middleware_name(following)
        end
      end
    end
  end
end
