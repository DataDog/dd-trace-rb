# frozen_string_literal: true

require_relative "../../ruby_version"

require "timeout" if Datadog::RubyVersion.is?("< 3.2")

module Datadog
  module DI
    module EL
      # Evaluator for expression language.
      #
      # @api private
      class Evaluator
        # Maximum wall-clock time allowed for evaluating a single `matches`
        # operator.
        MATCHES_TIMEOUT_SECONDS = 0.5

        # @param regexps [Array<Regexp>] Regexps precompiled from literal
        #   `matches` patterns, looked up by index by #matches_compiled.
        #    Empty when the expression has no `matches` pattern with
        #    a direct regular expression argument.
        def initialize(regexps = [])
          @regexps = regexps
        end

        attr_reader :regexps

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

        # Build a Regexp from a pattern string. On Ruby 3.2+ the per-match
        # timeout (MATCHES_TIMEOUT_SECONDS) is baked into the compiled
        # Regexp via the in-engine `timeout:` keyword, which interrupts the
        # matcher at every backtrack step and reliably bounds matcher
        # runtime regardless of pattern shape. On older Rubies the Regexp
        # carries no timeout; the bound is applied at match time by
        # #bounded_match? instead.
        #
        # @param needle [String] regexp source.
        # @return [Regexp] compiled regexp, with baked-in timeout on Ruby 3.2+.
        if Datadog::RubyVersion.is?(">= 3.2")
          def self.compile_regexp(needle)
            Regexp.new(needle, timeout: MATCHES_TIMEOUT_SECONDS)
          end
        else
          def self.compile_regexp(needle)
            Regexp.compile(needle)
          end
        end

        # Match +haystack+ against a regexp whose needle is computed at
        # evaluation time, so the Regexp cannot be precompiled. Literal needles are
        # precompiled by the Compiler and dispatched to #matches_compiled.
        #
        # @param haystack [String] string to match against.
        # @param needle [String] regexp source.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [Regexp::TimeoutError] (Ruby 3.2+) regexp engine exceeded MATCHES_TIMEOUT_SECONDS.
        # @raise [Timeout::Error] (Ruby < 3.2) Timeout.timeout fired.
        def matches(haystack, needle)
          bounded_match?(Evaluator.compile_regexp(needle), haystack)
        end

        # Match +haystack+ against a Regexp precompiled at expression-compile
        # time, looked up by index in +regexps+.
        #
        # @param haystack [String] string to match against.
        # @param index [Integer] position of the precompiled Regexp in +regexps+.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [Regexp::TimeoutError] (Ruby 3.2+) regexp engine exceeded MATCHES_TIMEOUT_SECONDS.
        # @raise [Timeout::Error] (Ruby < 3.2) Timeout.timeout fired.
        def matches_compiled(haystack, index)
          bounded_match?(regexps.fetch(index), haystack)
        end

        # Match +haystack+ against +re+, bounded at MATCHES_TIMEOUT_SECONDS
        # wall-clock.
        #
        # @param re [Regexp] regexp to match against.
        # @param haystack [String] string to match against.
        # @return [Boolean] whether the haystack matches the regexp.
        if Datadog::RubyVersion.is?(">= 3.2")
          def bounded_match?(re, haystack)
            # Uses Regexp#match? rather than =~ so that the
            # thread-local match data ($~, $1, ...) is not mutated as a side
            # effect of DI expression evaluation.
            re.match?(haystack)
          end
        else
          def bounded_match?(re, haystack)
            Timeout.timeout(MATCHES_TIMEOUT_SECONDS) do
              re.match?(haystack)
            end
          end
        end
        private :bounded_match?

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
