module Datadog
  # Defines some useful patching methods for integrations
  module Patcher
    def self.included(base)
      base.send(:extend, CommonMethods)
      base.send(:include, CommonMethods)
    end

    # Defines some common methods for patching, that can be used
    # at the instance, class, or module level.
    module CommonMethods
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

      def do_once(key = nil, options = {})
        # If already done, don't do again
        @done_once ||= Hash.new { |h, k| h[k] = {} }
        if @done_once.key?(key) && @done_once[key].key?(options[:for])
          return @done_once[key][options[:for]]
        end

        # Otherwise 'do'
        yield.tap do
          # Then add the key so we don't do again.
          @done_once[key][options[:for]] = true
        end
      end

      def done?(key, options = {})
        return false unless instance_variable_defined?(:@done_once)
        !@done_once.nil? && @done_once.key?(key) && @done_once[key].key?(options[:for])
      end
    end

    # Extend the common methods so they're available as a module function.
    extend(CommonMethods)
  end
end
