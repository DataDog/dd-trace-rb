# frozen_string_literal: true

module Datadog
  module DI
    module EL
      # Evaluator for expression language.
      #
      # @api private
      class Evaluator
        def ref(var)
          @context.fetch(var)
        end

        def iref(var)
          @context.fetch_ivar(var)
        end

        def len(var, var_name)
          case var
          when Array, String, Hash
            var.length
          else
            raise DI::Error::ExpressionEvaluationError, "Unsupported type for length: #{var.class}: #{var_name}"
          end
        end

        def is_empty(var, var_name)
          case var
          when nil, Numeric
            false
          when Array, String
            var.empty?
          else
            raise DI::Error::ExpressionEvaluationError, "Unsupported type for isEmpty: #{var.class}: #{var_name}"
          end
        end

        def is_undefined(var, var_name)
          var.nil?
        end

        def contains(haystack, needle)
          if String === haystack && String === needle or # standard:disable Style/AndOr
              Array === haystack
            haystack.include?(needle)
          else
            raise DI::Error::ExpressionEvaluationError, "Invalid arguments for contains: #{haystack}, #{needle}"
          end
        end

        def matches(haystack, needle)
          re = Regexp.compile(needle)
          !!(haystack =~ re)
        end

        def getmember(object, field)
          object.instance_variable_get("@#{field}")
        end

        def index(array_or_hash, index_or_key)
          case array_or_hash
          when Array
            case index_or_key
            when Integer
              array_or_hash[index_or_key]
            else
              raise DI::Error::ExpressionEvaluationError, "Invalid index value: #{index_or_key}"
            end
          when Hash
            array_or_hash[index_or_key]
          else
            raise DI::Error::ExpressionEvaluationError, "Invalid argument for index: #{array_or_hash}"
          end
        end

        def substring(object, from, to)
          unless String === object
            raise DI::Error::ExpressionEvaluationError, "Invalid type for substring: #{object}"
          end
          object[from...to]
        end

        def starts_with(haystack, needle)
          # To guard against running arbitrary customer code, check that
          # the haystack is a string. This does not help if customer
          # overrode String#start_with? but at least it's better than nothing.
          String === haystack && haystack.start_with?(needle)
        end

        def ends_with(haystack, needle)
          String === haystack && haystack.end_with?(needle)
        end

        def all(collection, &block)
          case collection
          when Array
            collection.all? do |item|
              block.call(item)
            end
          when Hash
            # For hashes, the expression language has both @it and
            # @key/@value. Manufacture @it from the key and value.
            collection.all? do |key, value|
              block.call([key, value], key, value)
            end
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for all: #{collection.class}"
          end
        end

        def any(collection, &block)
          case collection
          when Array
            collection.any? do |item|
              block.call(item)
            end
          when Hash
            collection.any? do |key, value|
              # For hashes, the expression language has both @it and
              # @key/@value. Manufacture @it from the key and value.
              block.call([key, value], key, value)
            end
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for any: #{collection.class}"
          end
        end

        def filter(collection, &block)
          case collection
          when Array
            collection.select do |item|
              block.call(item)
            end
          when Hash
            collection.select do |key, value|
              block.call([key, value], key, value)
            end.to_h
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for filter: #{collection.class}"
          end
        end

        def instanceof(object, cls_name)
          cls = object.class
          loop do
            if cls.name == cls_name
              return true
            end
            if supercls = cls.superclass # standard:disable Lint/AssignmentInCondition
              cls = supercls
            else
              return false
            end
          end
        end
      end
    end
  end
end
