module Datadog
  # Defines some useful patching methods for integrations
  module Patcher
    module_function

    def without_warnings
      # This is typically used when monkey patching functions such as
      # intialize, which Ruby advices you not to. Use cautiously.
      v = $VERBOSE
      $VERBOSE = nil
      begin
        yield
      ensure
        $VERBOSE = v
      end
    end
  end
end
