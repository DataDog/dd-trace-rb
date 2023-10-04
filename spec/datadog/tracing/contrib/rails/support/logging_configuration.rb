module Datadog
  module Tracing
    module Contrib
      module Rails
        module Test
          # Configure lograge in test
          module Lograge
            module_function

            def config(config, lograge)
              # `keep_original_rails_log` is important to prevent monkey patching from `lograge`
              #  which leads to flaky spec in the same test process
              config.lograge.keep_original_rails_log = true
              config.lograge.logger = config.logger

              config.lograge.enabled = !!lograge.enabled?
              config.lograge.custom_options = lograge.custom_options
            end
          end
        end
      end
    end
  end
end
