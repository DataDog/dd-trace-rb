# frozen_string_literal: true

require_relative "redactor"

module Datadog
  module DI
    # Serializes captured snapshot to primitive types, which are subsequently
    # serialized to JSON and sent to the backend.
    #
    # This class performs actual removal of sensitive values from the
    # snapshots. It uses Redactor to determine which values are sensitive
    # and need to be removed.
    #
    # Serializer normally ought not to invoke user (application) code,
    # to guarantee predictable performance. However, objects like ActiveRecord
    # models cannot be usefully serialized into primitive types without
    # custom logic (for example, the attributes are more than 3 levels
    # down from the top-level object which is the default capture depth,
    # thus they won't be captured at all). To accommodate complex objects,
    # there is an extension mechanism implemented permitting registration
    # of serializer callbacks for arbitrary types. Applications and libraries
    # definining such serializer callbacks should be very careful to
    # have predictable performance and avoid exceptions and infinite loops
    # and other such issues.
    #
    # All serialization methods take the names of the variables being
    # serialized in order to be able to redact values.
    #
    # @api private
    class Serializer
      def initialize(settings, redactor)
        @settings = settings
        @redactor = redactor
      end

      attr_reader :settings
      attr_reader :redactor

      # Serializes positional and keyword arguments to a method,
      # as obtained by a method probe.
      #
      # UI supports a single argument list only and does not distinguish
      # between positional and keyword arguments. We convert positional
      # arguments to keyword arguments ("arg1", "arg2", ...) and ensure
      # the positional arguments are listed first.
      def serialize_args(args, kwargs)
        counter = 0
        combined = args.each_with_object({}) do |value, c|
          counter += 1
          # Conversion to symbol is needed here to put args ahead of
          # kwargs when they are merged below.
          c[:"arg#{counter}"] = value
        end.update(kwargs)
        serialize_vars(combined)
      end

      # Serializes variables captured by a line probe.
      #
      # These are normally local variables that exist on a particular line
      # of executed code.
      def serialize_vars(vars)
        vars.each_with_object({}) do |(k, v), agg|
          agg[k] = serialize_value(k, v)
        end
      end

      private

      # Serializes a single named value.
      #
      # The name is necessary to perform sensitive data redaction.
      #
      # Returns a data structure comprised of only values of basic types
      # (integers, strings, arrays, hashes).
      #
      # Respects string length, collection size and traversal depth limits.
      def serialize_value(name, value, depth: settings.dynamic_instrumentation.max_capture_depth)
        if redactor.redact_type?(value)
          return {type: class_name(value.class), notCapturedReason: "redactedType"}
        end

        if name && redactor.redact_identifier?(name)
          return {type: class_name(value.class), notCapturedReason: "redactedIdent"}
        end

        serialized = {type: class_name(value.class)}
        case value
        when NilClass
          serialized.update(isNull: true)
        when Integer, Float, TrueClass, FalseClass
          serialized.update(value: value.to_s)
        when String, Symbol
          value = value.to_s
          max = settings.dynamic_instrumentation.max_capture_string_length
          if value.length > max
            serialized.update(notCapturedReason: "length", size: value.length)
            # steep misunderstands string slice types.
            # https://github.com/soutaro/steep/issues/1219
            value = (value[0...max] || "") + "..."
          end
          serialized.update(value: value)
        when Array
          if depth < 0
            serialized.update(notCapturedReason: "depth")
          else
            max = settings.dynamic_instrumentation.max_capture_collection_size
            if max != 0 && value.length > max
              serialized.update(notCapturedReason: "collectionSize", size: value.length)
              # same steep failure with array slices.
              # https://github.com/soutaro/steep/issues/1219
              value = value[0...max] || []
            end
            entries = value.map do |elt|
              serialize_value(nil, elt, depth: depth - 1)
            end
            serialized.update(elements: entries)
          end
        when Hash
          if depth < 0
            serialized.update(notCapturedReason: "depth")
          else
            max = settings.dynamic_instrumentation.max_capture_collection_size
            cur = 0
            entries = []
            value.each do |k, v|
              if max != 0 && cur >= max
                serialized.update(notCapturedReason: "collectionSize", size: value.length)
                break
              end
              cur += 1
              entries << [serialize_value(nil, k, depth: depth - 1), serialize_value(k, v, depth: depth - 1)]
            end
            serialized.update(entries: entries)
          end
        else
          if depth < 0
            serialized.update(notCapturedReason: "depth")
          else
            fields = {}
            max = settings.dynamic_instrumentation.max_capture_attribute_count
            cur = 0
            value.instance_variables.each do |ivar|
              if cur >= max
                serialized.update(notCapturedReason: "fieldCount", fields: fields)
                break
              end
              cur += 1
              fields[ivar] = serialize_value(ivar, value.instance_variable_get(ivar), depth: depth - 1)
            end
            serialized.update(fields: fields)
          end
        end
        serialized
      end

      # Returns the name for the specified class object.
      #
      # Ruby can have nameless classes, e.g. Class.new is a class object
      # with no name. We return a placeholder for such nameless classes.
      def class_name(cls)
        # We could call `cls.to_s` to get the "standard" Ruby inspection of
        # the class, but it is likely that user code can override #to_s
        # and we don't want to invoke user code.
        cls.name || "[Unnamed class]"
      end
    end
  end
end
