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
    # The result of serialization should not reference parameter values when
    # the values are mutable (currently, this only applies to string values).
    # Serializer will duplicate such mutable values, so that if method
    # arguments are captured at entry and then modified during method execution,
    # the serialized values from entry are correctly preserved.
    # Alternatively, we could pass a parameter to the serialization methods
    # which would control whether values are duplicated. This may be more
    # efficient but there would be additional overhead from passing this
    # parameter all the time and the API would get more complex.
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
      #
      # If +copy+ is true, all of the values are duplicated. This is meant
      # to be used when capturing method parameters at the beginning of
      # method execution, to preserve the initial values even if they are
      # modified during method execution.
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
          agg[k] = serialize_value(v, name: k)
        end
      end

      # Serializes a single named value.
      #
      # The name is needed to perform sensitive data redaction.
      #
      # In some cases, the value being serialized does not have a name
      # (for example, it is the return value of a method).
      # In this case +name+ can be nil.
      #
      # Returns a data structure comprised of only values of basic types
      # (integers, strings, arrays, hashes).
      #
      # Respects string length, collection size and traversal depth limits.
      def serialize_value(value, name: nil, depth: settings.dynamic_instrumentation.max_capture_depth)
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
          value = case value
          when String
            # This is the only place where we duplicate the value, currently.
            # All other values are immutable primitives (e.g. numbers).
            value.dup
          when Symbol
            value.to_s
          end
          max = settings.dynamic_instrumentation.max_capture_string_length
          if value.length > max
            serialized.update(truncated: true, size: value.length)
            value = value[0...max]
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
              serialize_value(elt, depth: depth - 1)
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
              entries << [serialize_value(k, depth: depth - 1), serialize_value(v, name: k, depth: depth - 1)]
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

            # MRI and JRuby 9.4.5+ preserve instance variable definition
            # order when calling #instance_variables. Previous JRuby versions
            # did not preserve order and returned the variables in arbitrary
            # order.
            #
            # The arbitrary order is problematic because 1) when there are
            # fewer instance variables than capture limit, the order in which
            # the variables are shown in UI will change from one capture to
            # the next and generally will be arbitrary to the user, and
            # 2) when there are more instance variables than capture limit,
            # *which* variables are captured will also change meaning user
            # looking at the UI may have "new" instance variables appear and
            # existing ones disappear as they are looking at multiple captures.
            #
            # For consistency, we should have some kind of stable order of
            # instance variables on all supported Ruby runtimes, so that the UI
            # stays consistent. Given that initial implementation of Ruby DI
            # does not support JRuby, we don't handle JRuby's lack of ordering
            # of #instance_variables here, but if JRuby is supported in the
            # future this may need to be addressed.
            ivars = value.instance_variables

            ivars.each do |ivar|
              if cur >= max
                serialized.update(notCapturedReason: "fieldCount", fields: fields)
                break
              end
              cur += 1
              fields[ivar] = serialize_value(value.instance_variable_get(ivar), name: ivar, depth: depth - 1)
            end
            serialized.update(fields: fields)
          end
        end
        serialized
      end

      private

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
