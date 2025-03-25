# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Support
        module_function

        # Avoid loading a constant if it's autoloaded but not yet loaded.
        # Since autoloaded constants return non-nil for `defined?`, even if not loaded, we need a special check of them.
        def autoloaded?(base_module, constant)
          # Autoload constants return `constant` for `defined?`, but that doesn't mean they are loaded...
          base_module.const_defined?(constant) &&
            # ... to check that we need to call `autoload?`. If it returns `nil`, it's loaded.
            base_module.autoload?(constant).nil?
        end
      end
    end
  end
end
