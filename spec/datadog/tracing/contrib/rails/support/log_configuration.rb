module Datadog
  module Tracing
    module Contrib
      module Rails
        module Test
          # Configure logging in test
          class LogConfiguration
            def initialize(example_group)
              @example_group = example_group
            end

            def setup(config)
              config.log_tags = example_group.log_tags if example_group.log_tags

              config.logger = if ENV['USE_TAGGED_LOGGING'] == true
                                ::ActiveSupport::TaggedLogging.new(example_group.logger)
                              else
                                example_group.logger
                              end

              # Not to use ANSI color codes when logging information
              config.colorize_logging = false

              if config.respond_to?(:lograge)
                LogrageConfiguration.setup!(config, OpenStruct.new(example_group.lograge_options))
              end

              # Semantic Logger settings should be exclusive to `ActiveSupport::TaggedLogging` and `Lograge`
              if config.respond_to?(:rails_semantic_logger)
                config.rails_semantic_logger.add_file_appender = false
                config.semantic_logger.add_appender(logger: config.logger)
              end
            end

            private

            attr_reader :example_group

            # Configure lograge in test
            module LogrageConfiguration
              module_function

              def setup!(config, lograge)
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
end
