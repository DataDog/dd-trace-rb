module Datadog
  module Contrib
    module Rack
      # Provides instrumentation for `rack`
      module MiddlewarePatcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          # Patch middleware
          require_relative 'middlewares'
        end
      end

      # Provides instrumentation for Rack middleware names
      module MiddlewareNamePatcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          patch_middleware_names
        end

        def patch_middleware_names
          retain_middleware_name(get_option(:application))
        rescue => e
          # We can safely ignore these exceptions since they happen only in the
          # context of middleware patching outside a Rails server process (eg. a
          # process that doesn't serve HTTP requests but has Rails environment
          # loaded such as a Resque master process)
          Logger.log.debug("Error patching middleware stack: #{e}")
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

      # Applies multiple patches
      module Patcher
        PATCHERS = [
          MiddlewarePatcher,
          MiddlewareNamePatcher
        ].freeze

        module_function

        def patched?
          PATCHERS.all?(&:patched?)
        end

        def target_version
          Integration.version
        end

        def patch
          MiddlewarePatcher.patch unless MiddlewarePatcher.patched?

          # Patch middleware names
          if !MiddlewareNamePatcher.patched? && get_option(:middleware_names)
            if get_option(:application)
              MiddlewareNamePatcher.patch
            else
              Datadog::Logger.log.warn(%(
              Rack :middleware_names requires you to also pass :application.
              Middleware names have NOT been patched; please provide :application.
              e.g. use: :rack, middleware_names: true, application: my_rack_app).freeze)
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:rack].get_option(option)
        end
      end
    end
  end
end
