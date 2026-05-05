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
    # Note: "self" cannot be used as a parameter name in Ruby, therefore
    # there should never be a conflict between instance variable
    # serialization and method parameters.
    #
    # @api private
    class Serializer
      # Exception classes that should never be caught during serialization.
      # These represent fatal conditions (signals, interrupts, system exit)
      # that must propagate to the caller.
      FATAL_EXCEPTION_CLASSES = [SignalException, Interrupt, SystemExit].freeze

      # Third-party library integration / custom serializers.
      #
      # Dynamic instrumentation has limited payload sizes, and for efficiency
      # reasons it is not desirable to transmit data to Datadog that will
      # never contain useful information. Additionally, due to depth limits,
      # desired data may not even be included in payloads when serialized
      # with the default, naive serializer. Therefore, custom objects like
      # ActiveRecord model instances may need custom serializers.
      #
      # CUSTOMER NOTE: The API for defining custom serializers is not yet
      # finalized. Please create an issue at
      # https://github.com/datadog/dd-trace-rb/issues describing the
      # object(s) you wish to serialize so that we can ensure your use case
      # will be supported as the library evolves.
      #
      # Note that the current implementation does not permit defining a
      # serializer for a particular class, which is the simplest use case.
      # This is because the library itself does not need this functionality
      # yet, and it won't help for ActiveRecord models (that derive from
      # a common base class but are all of different classes) or for Mongoid
      # models (that do not have a common base class at all but include a
      # standard Mongoid module).
      #
      # Important: these serializers are NOT used in log messages.
      # They are only used for variables that are captured in the snapshots.
      #
      # Exception handling: If a custom serializer's condition lambda raises
      # an exception (e.g., regex match against invalid UTF-8 strings), the
      # exception will be logged at WARN level, then the serializer will be
      # skipped and the next serializer will be tried. This prevents custom
      # serializers from breaking the entire serialization process.
      #
      # IMPORTANT: Custom serializers MUST produce data that can be JSON-encoded.
      # Specifically, custom serializers MUST NOT produce strings with binary
      # encoding (ASCII-8BIT) containing non-ASCII code points (bytes >= 0x80)
      # that cannot be automatically transcoded to UTF-8. Such strings will
      # cause JSON encoding to fail, which will result in the probe being
      # disabled and an ERROR status being reported. If your data contains
      # binary content, encode it to a text representation (e.g., Base64,
      # hex string, or UTF-8 with replacement characters) before returning
      # it from the custom serializer.
      @@flat_registry = []
      def self.register(condition: nil, &block)
        @@flat_registry << {condition: condition, proc: block}
      end

      def initialize(settings, redactor, telemetry: nil)
        @settings = settings
        @redactor = redactor
        @telemetry = telemetry
      end

      attr_reader :settings
      attr_reader :redactor
      attr_reader :telemetry

      def combine_args(args, kwargs, target_self)
        counter = 0
        combined = args.each_with_object({}) do |value, c|
          counter += 1
          # Conversion to symbol is needed here to put args ahead of
          # kwargs when they are merged below.
          c[:"arg#{counter}"] = value
        end.update(kwargs)
        combined[:self] = target_self
        combined
      end

      # Serializes positional and keyword arguments to a method,
      # as obtained by a method probe.
      #
      # UI supports a single argument list only and does not distinguish
      # between positional and keyword arguments. We convert positional
      # arguments to keyword arguments ("arg1", "arg2", ...) and ensure
      # the positional arguments are listed first.
      #
      # Instance variables are technically a hash just like kwargs,
      # we take them as a separate parameter to avoid a hash merge
      # in upstream code.
      def serialize_args(args, kwargs, target_self,
        depth: settings.dynamic_instrumentation.max_capture_depth,
        attribute_count: settings.dynamic_instrumentation.max_capture_attribute_count)
        combined = combine_args(args, kwargs, target_self)
        serialize_vars(combined, depth: depth, attribute_count: attribute_count)
      end

      # Serializes variables captured by a line probe.
      #
      # These are normally local variables that exist on a particular line
      # of executed code.
      def serialize_vars(vars,
        depth: settings.dynamic_instrumentation.max_capture_depth,
        attribute_count: settings.dynamic_instrumentation.max_capture_attribute_count)
        vars.each_with_object({}) do |(k, v), agg|
          agg[k] = serialize_value(v, name: k, depth: depth, attribute_count: attribute_count)
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
      def serialize_value(value, name: nil,
        depth: settings.dynamic_instrumentation.max_capture_depth,
        attribute_count: nil,
        type: nil)
        attribute_count ||= settings.dynamic_instrumentation.max_capture_attribute_count
        cls = type || value.class
        begin
          if redactor.redact_type?(value)
            return {type: class_name(cls), notCapturedReason: "redactedType"}
          end

          if name && redactor.redact_identifier?(name)
            return {type: class_name(cls), notCapturedReason: "redactedIdent"}
          end

          @@flat_registry.each do |entry|
            condition = entry[:condition]
            if condition
              begin
                condition_result = condition.call(value)
              rescue => e
                # If a custom serializer condition raises an exception (e.g., regex match
                # against invalid UTF-8), skip it and continue with the next serializer.
                # We don't want custom serializer conditions to break the entire serialization.
                #
                # Custom serializers may be defined by customers (in which case we should
                # surface errors so they can fix their serializers) or they may be defined
                # internally by dd-trace-rb (in which case we need to fix them). We use
                # WARN level to surface these errors in either case.
                Datadog.logger.warn("DI: Custom serializer condition failed: #{e.class}: #{e.message}")
                telemetry&.report(e, description: "Custom serializer condition failed")
                next
              end

              if condition_result
                serializer_proc = entry.fetch(:proc)
                return serializer_proc.call(self, value, name: nil, depth: depth)
              end
            end
          end

          serialized = {type: class_name(cls)}
          # https://github.com/soutaro/steep/issues/1860
          # @type var serialized: untyped
          case value
          when NilClass
            serialized.update(isNull: true)
          when Integer, Float, TrueClass, FalseClass
            serialized.update(value: value.to_s)
          when Time
            # This path also handles DateTime values although they do not need
            # to be explicitly added to the case statement.
            serialized.update(value: value.iso8601)
          when Date
            serialized.update(value: value.to_s)
          when String, Symbol
            need_dup = false
            value = if String === value
              # This is the only place where we duplicate the value, currently.
              # All other values are immutable primitives (e.g. numbers).
              # However, do not duplicate if the string is frozen, or if
              # it is later truncated.
              need_dup = !value.frozen?
              value
            else
              value.to_s
            end

            # Handle binary strings and invalid UTF-8 by escaping to JSON-safe format.
            # See escape_binary_string for details on the escaping format.
            #
            # Truncate binary data BEFORE escaping to avoid cutting mid-escape-sequence.
            # For regular strings, the limit is applied to string length in characters.
            max = settings.dynamic_instrumentation.max_capture_string_length

            if value.encoding == Encoding::BINARY || !value.valid_encoding?
              # Truncate binary data BEFORE escaping to avoid cutting mid-escape-sequence
              # For invalid encodings, use bytesize instead of length to avoid encoding errors
              original_size = value.bytesize
              if original_size > max
                serialized.update(truncated: true, size: original_size)
                value = value.byteslice(0...max)
              end
              value = escape_binary_string(value) # steep:ignore ArgumentTypeMismatch
              false # Already converted to a new string
            else
              # Truncate non-binary strings
              if value.length > max
                serialized.update(truncated: true, size: value.length)
                value = value[0...max]
                need_dup = false
              end

              value = value.dup if need_dup
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
                if cur >= attribute_count
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
        rescue Exception => exc # standard:disable Lint/RescueException
          # Re-raise fatal exceptions that should not be caught
          # (signals, interrupts, system exit)
          raise if FATAL_EXCEPTION_CLASSES.any? { |klass| exc.is_a?(klass) }

          # Catch all other exceptions including SystemStackError and NoMemoryError.
          # These inherit from Exception (not StandardError) but can occur during
          # serialization (e.g., infinite recursion in custom serializers, memory
          # exhaustion from large objects) and should return a safe structure
          # rather than propagating to the transport layer.
          telemetry&.report(exc, description: "Error serializing")
          {type: class_name(cls), notSerializedReason: exc.to_s}
        end
      end

      # This method is used for serializing arbitrary values into log messages.
      # Because the output is meant to be human-readable, we cannot use
      # the "normal" serialization format which is meant to be machine-readable.
      # Serialize objects with depth of 1 and include the class name.
      #
      # Note that this method does not (currently) utilize the custom
      # serializers that the "normal" serialization logic uses.
      #
      # This serializer differs from the RFC in two ways:
      # 1. We omit the middle of long strings rather than the end,
      #    and also the inner entries in arrays/hashes/objects.
      # 2. We use Ruby-ish syntax for hashes and objects.
      #
      # We also use the Ruby-like syntax for symbols, which don't exist
      # in other languages.
      def serialize_value_for_message(value, depth = 1)
        # This method is more verbose than "normal" Ruby code to avoid
        # array allocations.
        case value
        when NilClass
          'nil'
        when Integer, Float, TrueClass, FalseClass, Time, Date
          value.to_s
        when String
          serialize_string_or_symbol_for_message(value)
        when Symbol
          ':' + serialize_string_or_symbol_for_message(value)
        when Array
          return '...' if depth <= 0

          max = max_capture_collection_size_for_message
          if value.length > max
            value_ = value[0...max - 1] || []
            value_ << '...'
            value_ << value[-1]
            value = value_
          end
          '[' + value.map do |item|
            serialize_value_for_message(item, depth - 1)
          end.join(', ') + ']'
        when Hash
          return '...' if depth <= 0

          max = max_capture_collection_size_for_message
          keys = value.keys
          truncated = false
          if value.length > max
            keys_ = keys[0...max - 1] || []
            keys_ << keys[-1]
            keys = keys_
            truncated = true
          end
          serialized = keys.map do |key|
            "#{serialize_value_for_message(key, depth - 1)} => #{serialize_value_for_message(value[key], depth - 1)}"
          end
          if truncated
            serialized[serialized.length] = serialized[serialized.length - 1]
            serialized[serialized.length - 2] = '...'
          end
          "{#{serialized.join(", ")}}"
        else
          return '...' if depth <= 0

          vars = value.instance_variables
          truncated = false
          max = max_capture_attribute_count_for_message
          if vars.length > max
            vars_ = vars[0...max - 1] || []
            vars_ << vars[-1]
            truncated = true
            vars = vars_
          end
          serialized = vars.map do |var|
            # +var+ here is always the instance variable name which is a
            # symbol, we do not need to run it through our serializer.
            "#{var}=#{serialize_value_for_message(value.send(:instance_variable_get, var), depth - 1)}"
          end
          if truncated
            serialized << serialized.last
            serialized[-2] = '...'
          end
          serialized = if serialized.any?
            ' ' + serialized.join(' ')
          end
          "#<#{class_name(value.class)}#{serialized}>"
        end
      rescue => exc
        telemetry&.report(exc, description: "Error serializing for message")
        # TODO class_name(foo) can also fail, which we don't handle here.
        # Telemetry reporting could potentially also fail?
        "#<#{class_name(value.class)}: serialization error>"
      end

      private

      MAX_MESSAGE_COLLECTION_SIZE = 3
      MAX_MESSAGE_ATTRIBUTE_COUNT = 5

      def max_capture_collection_size_for_message
        max = settings.dynamic_instrumentation.max_capture_collection_size
        if max > MAX_MESSAGE_COLLECTION_SIZE
          max = MAX_MESSAGE_COLLECTION_SIZE
        end
        max
      end

      def max_capture_attribute_count_for_message
        max = settings.dynamic_instrumentation.max_capture_attribute_count
        if max > MAX_MESSAGE_ATTRIBUTE_COUNT
          max = MAX_MESSAGE_ATTRIBUTE_COUNT
        end
        max
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

      def serialize_string_or_symbol_for_message(value)
        max = settings.dynamic_instrumentation.max_capture_string_length
        if max > 100
          max = 100
        end
        value = value.to_s
        if (length = value.length) > max
          if max < 5
            value[0...max]
          else
            upper = length - max / 2 + 1
            if max % 2 == 0
              upper += 1
            end
            value[0...max / 2 - 1] + '...' + value[upper...length]
          end
        else
          value
        end
      end

      # Escapes a binary string or invalid UTF-8 string to a JSON-safe format.
      #
      # IMPORTANT: This method should ONLY be called with either:
      # 1. True binary strings (encoding == Encoding::BINARY / ASCII-8BIT)
      # 2. Strings with invalid encoding (!value.valid_encoding?)
      #
      # Calling this method with valid UTF-8 strings will produce incorrect output.
      #
      # Binary data (ASCII-8BIT encoding) or strings with invalid encoding are
      # converted to an escaped string in the format: b'...' with hex escapes
      # for non-printable bytes.
      #
      # The output format matches other Datadog tracer libraries for consistency
      # across language implementations. The output is JSON-serializable.
      #
      # Examples:
      #   "Hello".b -> "b'Hello'"
      #   "\x80\xFF".b -> "b'\\x80\\xff'"
      #   "\x80".force_encoding('UTF-8') -> "b'\\x80'" (invalid UTF-8)
      #
      # @param binary_string [String] A string with ASCII-8BIT encoding or invalid encoding
      # @return [String] Escaped string with UTF-8 encoding
      def escape_binary_string(binary_string)
        result = +"b'"
        binary_string.each_byte do |byte|
          result << case byte
          when 0x09 # \t
            '\\t'
          when 0x0A # \n
            '\\n'
          when 0x0D # \r
            '\\r'
          when 0x27 # '
            "\\'"
          when 0x5C # \
            '\\\\'
          when 0x20..0x7E # Printable ASCII (space through ~)
            byte.chr
          else
            # Non-printable: use \xHH format
            format('\\x%02x', byte)
          end
        end
        result << "'"
        result
      end
    end
  end
end
