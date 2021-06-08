require 'ddtrace/utils/only_once'

module Datadog
  # Deprecated: This module should no longer be included. It's only being kept around for backwards compatibility
  # concerns regarding customer usage.
  module Patcher
    INCLUDED_WARN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new
    DO_ONCE_USAGE_WARN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

    def self.included(base)
      INCLUDED_WARN_ONLY_ONCE.run do
        Datadog.logger.warn(
          'Including Datadog::Patcher is deprecated. ' \
          'For the #do_once behavior, use Datadog::Utils::OnlyOnce instead. ' \
          'For the #without_warnings behavior, use Datadog::Patcher.without_warnings { ... } as a module function.'
        )
      end

      base.extend(CommonMethods)
      base.include(CommonMethods)
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
        DO_ONCE_USAGE_WARN_ONLY_ONCE.run do
          Datadog.logger.warn('Datadog::Patcher#do_once is deprecated. Use Datadog::Utils::OnlyOnce instead.')
        end

        # If already done, don't do again
        @done_once ||= Hash.new { |h, k| h[k] = {} }
        return @done_once[key][options[:for]] if @done_once.key?(key) && @done_once[key].key?(options[:for])

        # Otherwise 'do'
        yield.tap do
          # Then add the key so we don't do again.
          @done_once[key][options[:for]] = true
        end
      end

      def done?(key, options = {})
        DO_ONCE_USAGE_WARN_ONLY_ONCE.run do
          Datadog.logger.warn('Datadog::Patcher#done? is deprecated. Use Datadog::Utils::OnlyOnce instead.')
        end

        return false unless instance_variable_defined?(:@done_once)

        !@done_once.nil? && @done_once.key?(key) && @done_once[key].key?(options[:for])
      end
    end

    # Extend the common methods so they're available as a module function.
    extend(CommonMethods)
  end
end
