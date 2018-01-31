module Datadog
  module Contrib
    module Rails
      module ActionController
        module Callbacks
          # Callbacks module specifically for Rails 5.0
          module Rails50
            def self.included(base)
              base.class_eval do
                alias_method :_process_action_callbacks_without_datadog, :_process_action_callbacks
                alias_method :_process_action_callbacks, :_process_action_callbacks_with_datadog
              end
            end

            def _process_action_callbacks_with_datadog
              _process_action_callbacks_without_datadog.tap do |chain|
                unless chain.class < ActiveSupport::Callbacks::Rails50::CallbackChain
                  chain.extend(ActiveSupport::Callbacks::Rails50::CallbackChain)
                end
              end
            end
          end
        end
      end
    end
  end
end
