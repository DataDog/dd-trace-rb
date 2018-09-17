module Datadog
  module Contrib
    module Rack
      # Provides instrumentation for `rack`
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:rack)
        end

        def patch
          # Patch middleware
          do_once(:rack) do
            require_relative 'middlewares'
          end

          # Patch middleware names
          if !done?(:rack_middleware_names) && get_option(:middleware_names)
            if get_option(:application)
              do_once(:rack_middleware_names) do
                patch_middleware_names
              end
            else
              Datadog::Tracer.log.warn(%(
              Rack :middleware_names requires you to also pass :application.
              Middleware names have NOT been patched; please provide :application.
              e.g. use: :rack, middleware_names: true, application: my_rack_app).freeze)
            end
          end
        rescue StandardError => e
          Datadog::Tracer.log.error("Unable to apply Rack integration: #{e}")
        end

        def patch_middleware_names
          retain_middleware_name(get_option(:application))
        rescue => e
          # We can safely ignore these exceptions since they happen only in the
          # context of middleware patching outside a Rails server process (eg. a
          # process that doesn't serve HTTP requests but has Rails environment
          # loaded such as a Resque master process)
          Tracer.log.debug("Error patching middleware stack: #{e}")
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

          following = if middleware.instance_variable_defined?('@app')
                        middleware.instance_variable_get('@app')
                      end

          retain_middleware_name(following)
        end

        def get_option(option)
          Datadog.configuration[:rack].get_option(option)
        end
      end
    end
  end
end
