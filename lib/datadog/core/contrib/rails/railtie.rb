# frozen_string_literal: true

require_relative 'utils'
require_relative '../../environment/process'
require_relative '../../process_discovery'

module Datadog
  module Core
    module Contrib
      module Rails
        # Railtie for core Rails setup that benefits all Datadog products.
        class Railtie < ::Rails::Railtie
          def self.after_initialize
            if Datadog.configuration.experimental_propagate_process_tags_enabled
              Datadog::Core::Environment::Process.rails_application_name =
                Datadog::Core::Contrib::Rails::Utils.app_name
            end

            # Process Discovery should always publish after_initialize since it has access to more information
            Datadog::Core::ProcessDiscovery.publish(Datadog.configuration)
          end

          # Registered after the method definition so the method exists if on_load fires immediately
          # (which happens when the Railtie is loaded into an already-initialized Rails app).
          ::ActiveSupport.on_load(:after_initialize) do
            Datadog::Core::Contrib::Rails::Railtie.after_initialize
          end
        end
      end
    end
  end
end
