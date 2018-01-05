module Datadog
  module Contrib
    module Sidekiq
      # Provides instrumentation support for Sidekiq
      module Patcher
        include Base
        VERSION_REQUIRED = Gem::Version.new('4.0.0')
        register_as :sidekiq
        option :service_name, default: 'sidekiq'
        option :tracer, default: Datadog.tracer

        module_function

        def patch
          return unless compatible?

          require_relative 'tracer'

          ::Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.add(Sidekiq::Tracer)
            end
          end
        end

        def compatible?
          defined?(::Sidekiq) &&
            Gem::Version.new(::Sidekiq::VERSION) >= VERSION_REQUIRED
        end
      end
    end
  end
end
