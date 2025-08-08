# frozen_string_literal: true

module Datadog
  module DI
    module ProbeFileLoader
      # Railtie class initializes dynamic instrumentation contrib code
      # in Rails environments.
      class Railtie < Rails::Railtie
        initializer 'datadog.dynamic_instrumentation.load_probe_file' do |app| # steep:ignore
          ProbeFileLoader.load_now
        end
      end
    end
  end
end
