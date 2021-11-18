require 'ddtrace'

module Datadog
  module Security
    module Contrib
      # Auto-instrumentation for security integrations
      # TODO: this implementation is trivial, check for shareable code with tracer
      module AutoInstrument
        def self.patch_all
          integrations = []

          Datadog::Security::Contrib::Integration.registry.each do |_name, integration|
            next unless integration.klass.auto_instrument?

            integrations << integration.name
          end

          Datadog::Security.configure do |c|
            integrations.each do |integration_name|
              c.use integration_name
            end
          end
        end
      end
    end
  end
end
