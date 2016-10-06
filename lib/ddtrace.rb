# Datadog initialization for frameworks
#
# When installed as a gem you can auto instrument the code with:
#
# Rails -> add the following to your initialization sequence:
# ```
#   config.gem 'ddtrace'
# ```
require 'ddtrace/contrib/rails/framework'

if defined?(Rails::VERSION)
  if Rails::VERSION::MAJOR.to_i >= 3
    module Datadog
      # some stuff
      class Railtie < Rails::Railtie
        initializer 'ddtrace.instrument' do |app|
          Datadog::Instrument::RailsFramework.init_plugin(config: app.config)
        end
      end
    end
  end
end
