# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rails
        # Railtie to include AutoInstrumentation in rails loading
        class AutoInstrumentRailtie < ::Rails::Railtie
          # we want to load before config initializers so that any user supplied config
          # in config/initializers/datadog.rb will take precedence
          initializer 'datadog.start_appsec', before: :load_config_initializers do
            Datadog::AppSec::Contrib::AutoInstrument.patch_all!
          end
        end
      end
    end
  end
end
