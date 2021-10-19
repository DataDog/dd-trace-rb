require 'ddtrace'

module Datadog
  module Security
    module Contrib
      module AutoInstrument
        def self.patch_all
          integrations = []

          Datadog::Security::Contrib::Integration.registry.each do |name, integration|
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

