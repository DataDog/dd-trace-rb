# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Provides instrumentation for `rack`
        module MiddlewarePatcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            # Patch middleware
            require_relative "middlewares"
          end
        end

        # Provides instrumentation for Rack middleware names
        module MiddlewareNamePatcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            patch_middleware_names
          end

          def self.patch_middleware_names
            retain_middleware_name(get_option(:application))
          rescue => e
            # We can safely ignore these exceptions since they happen only in the
            # context of middleware patching outside a Rails server process (eg. a
            # process that doesn't serve HTTP requests but has Rails environment
            # loaded such as a Resque master process)
            Datadog.logger.debug("Error patching middleware stack: #{e.class}: #{e.message}")
          end

          def self.retain_middleware_name(middleware)
            return unless middleware&.respond_to?(:call)

            middleware.singleton_class.class_eval do
              alias_method :__call, :call

              def call(env)
                env["RESPONSE_MIDDLEWARE"] = self.class.to_s
                __call(env)
              end
            end

            following = (middleware.instance_variable_get(:@app) if middleware.instance_variable_defined?(:@app))

            retain_middleware_name(following)
          end

          def self.get_option(option)
            Datadog.configuration.tracing[:rack].get_option(option)
          end
        end

        # Applies multiple patches
        module Patcher
          PATCHERS = [
            MiddlewarePatcher,
            MiddlewareNamePatcher,
          ].freeze

          def self.patched?
            PATCHERS.all?(&:patched?)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            MiddlewarePatcher.patch unless MiddlewarePatcher.patched?

            # Patch middleware names
            if !MiddlewareNamePatcher.patched? && get_option(:middleware_names)
              if get_option(:application)
                MiddlewareNamePatcher.patch
              else
                Datadog.logger.warn(
                  %(
                Rack :middleware_names requires you to also pass :application.
                Middleware names have NOT been patched; please provide :application.
                e.g. use: :rack, middleware_names: true, application: my_rack_app),
                )
              end
            end
          end

          def self.get_option(option)
            Datadog.configuration.tracing[:rack].get_option(option)
          end

          def self.patch_successful
            MiddlewarePatcher.patch_successful || MiddlewareNamePatcher.patch_successful
          end

          def self.patch_error_result
            MiddlewarePatcher.patch_error_result || MiddlewareNamePatcher.patch_error_result
          end
        end
      end
    end
  end
end
