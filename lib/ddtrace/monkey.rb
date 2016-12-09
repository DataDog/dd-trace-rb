require 'ddtrace/contrib/autopatch'
module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  module Monkey
    module_function

    def patch_all
      Datadog::Contrib::Autopatch.autopatch
    end

    def get_patched_modules
      Datadog::Contrib::Autopatch.get_patched_modules
    end
  end
end
