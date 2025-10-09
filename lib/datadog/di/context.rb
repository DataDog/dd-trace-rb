# frozen_string_literal: true

module Datadog
  module DI
    # Contains local and instance variables used when evaluating
    # expressions in DI Expression Language.
    #
    # @api private
    class Context
      def initialize(probe:, settings:, serializer:, locals: nil,
        # In Ruby everything is a method, therefore we should always have
        # a target self. However, if we are not capturing a snapshot,
        # there is no need to pass in the target self.
        target_self: nil,
        path: nil, caller_locations: nil,
        serialized_entry_args: nil,
        return_value: nil, duration: nil, exception: nil)
        @probe = probe
        @settings = settings
        @serializer = serializer
        @locals = locals
        @target_self = target_self
        @path = path
        @caller_locations = caller_locations
        @serialized_entry_args = serialized_entry_args
        @return_value = return_value
        @duration = duration
        @exception = exception
      end

      attr_reader :probe
      attr_reader :settings
      attr_reader :serializer
      attr_reader :locals
      attr_reader :target_self
      # Actual path of the instrumented file.
      attr_reader :path
      # TODO check how many stack frames we should be keeping/sending,
      # this should be all frames for enriched probes and no frames for
      # non-enriched probes?
      attr_reader :caller_locations
      attr_reader :serialized_entry_args
      # Return value for the method, for a method probe
      attr_reader :return_value
      # How long the method took to execute, for a method probe
      attr_reader :duration
      # Exception raised by the method, if any, for a method probe
      attr_reader :exception

      def serialized_locals
        # TODO cache?
        locals && serializer.serialize_vars(locals,
          depth: probe.max_capture_depth || settings.dynamic_instrumentation.max_capture_depth,
          attribute_count: probe.max_capture_attribute_count || settings.dynamic_instrumentation.max_capture_attribute_count,)
      end

      def fetch(var_name)
        unless locals
          # TODO return "undefined" instead?
          return nil
        end
        locals[var_name.to_sym]
      end

      def fetch_ivar(var_name)
        target_self.instance_variable_get(var_name)
      end
    end
  end
end
