# frozen_string_literal: true

require_relative '../../ruby_version'

require 'timeout' if Datadog::RubyVersion.is?('< 3.2')

module Datadog
  module DI
    module EL
      # Evaluator for expression language.
      #
      # @api private
      class Evaluator
        # Maximum wall-clock time allowed for evaluating a single `matches`
        # operator. Pathological regexp patterns (catastrophic backtracking)
        # can otherwise run for many seconds on short inputs and stall the
        # thread executing the probe.
        MATCHES_TIMEOUT_SECONDS = 0.5

        # @param regexps [Array<Regexp>] Regexps precompiled from literal
        #   `matches` patterns (see Compiler#precompile_regexp), looked up by
        #   index by #matches_compiled. Empty when the expression has no
        #   literal `matches` pattern.
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
        # #apply_match instead.
        #
        # Called at expression-compile time for literal needles (see
        # Compiler#precompile_regexp) and at evaluation time for
        # dynamically-computed needles (see #matches).
        #
        # @param needle [String] regexp source.
        # @return [Regexp] compiled regexp, with baked-in timeout on Ruby 3.2+.
        #
        # The running Ruby version is fixed for the process, so the branch is
        # resolved once at load time by defining the method per-version rather
        # than checking the version on every call.
        if Datadog::RubyVersion.is?('>= 3.2')
          def self.compile_regexp(needle)
            Regexp.new(needle, timeout: MATCHES_TIMEOUT_SECONDS)
          end
        else
          def self.compile_regexp(needle)
            Regexp.compile(needle)
          end
        end

        # Apply a regexp match where the needle is computed at evaluation
        # time, so the Regexp cannot be precompiled. Literal needles are
        # precompiled by the Compiler and dispatched to #matches_compiled.
        #
        # @param haystack [String] string to match against.
        # @param needle [String] regexp source.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [Regexp::TimeoutError] (Ruby 3.2+) regexp engine exceeded MATCHES_TIMEOUT_SECONDS.
        # @raise [Timeout::Error] (Ruby < 3.2) Timeout.timeout fired.
        def matches(haystack, needle)
          apply_match(Evaluator.compile_regexp(needle), haystack)
        end

        # Apply a Regexp precompiled at expression-compile time, looked up
        # by index in +regexps+. Avoids recompiling the pattern on every
        # probe firing.
        #
        # @param haystack [String] string to match against.
        # @param index [Integer] position of the precompiled Regexp in +regexps+.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [Regexp::TimeoutError] (Ruby 3.2+) regexp engine exceeded MATCHES_TIMEOUT_SECONDS.
        # @raise [Timeout::Error] (Ruby < 3.2) Timeout.timeout fired.
        def matches_compiled(haystack, index)
          apply_match(regexps.fetch(index), haystack)
        end

        # Apply +re+ to +haystack+, bounded at MATCHES_TIMEOUT_SECONDS
        # wall-clock. Uses Regexp#match? rather than =~ so that the
        # thread-local match data ($~, $1, ...) is not mutated as a side
        # effect of DI expression evaluation.
        #
        # On Ruby 3.2+ the bound is enforced by the regexp engine itself
        # (baked into +re+ by .compile_regexp). On older Rubies we wrap the
        # match in Timeout.timeout, which uses Thread#raise: Onigmo polls
        # for pending interrupts at certain points during matching, so this
        # bounds the runtime for many patterns but is best-effort -- pattern
        # shapes that never reach an interrupt-poll point during their hot
        # loop (see Ruby bug #18144) can still overrun the timeout.
        # Migrating to Ruby 3.2+ is the only complete fix.
        #
        # The Timeout.timeout wrap is safe only because re.match?(haystack)
        # is a side-effect-free pure computation: Thread#raise can interrupt
        # at any point, so do not widen this block to include mutation, IO,
        # or resource cleanup.
        #
        # @param re [Regexp] regexp to apply.
        # @param haystack [String] string to match against.
        # @return [Boolean] whether the haystack matches the regexp.
        #
        # Defined per-version at load time (see .compile_regexp) so the
        # version branch is not re-evaluated on every match.
        if Datadog::RubyVersion.is?('>= 3.2')
          def apply_match(re, haystack)
            re.match?(haystack)
          end
        else
          def apply_match(re, haystack)
            Timeout.timeout(MATCHES_TIMEOUT_SECONDS) do
              re.match?(haystack)
            end
          end
        end
        private :apply_match

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
