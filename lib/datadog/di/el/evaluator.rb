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

        # Number of collection items processed between cooperative
        # evaluation-deadline checks; evaluation aborts within one
        # interval's worth of items past the deadline.
        EVALUATION_DEADLINE_CHECK_INTERVAL = 64

        # Message of DI::Error::EvaluationTimeout, raised by the
        # cooperative evaluation-deadline checks.
        EVALUATION_TIMEOUT_MESSAGE = "expression evaluation timeout"

        # Built-in Array#each, resolved once at load and bound per
        # invocation: #filter's iteration then dispatches no customer
        # each override during probe evaluation.
        ARRAY_EACH = Array.instance_method(:each)
        private_constant :ARRAY_EACH

        # @param regexps [Array<Regexp>] Regexps precompiled from literal
        #   `matches` patterns, looked up by index by #matches_compiled.
        #    Empty when the expression has no `matches` pattern with
        #    a direct regular expression argument.
        def initialize(regexps = [])
          @regexps = regexps
        end

        attr_reader :regexps

        # Raises DI::Error::EvaluationTimeout when the evaluation deadline
        # has been exceeded, aborting collection-operator iteration
        # cooperatively.
        #
        # @param item_index [Integer] zero-based index of the collection
        #   element being processed.
        # @param deadline [Float, nil] invocation-local evaluation deadline,
        #   threaded from the compiled #evaluate into the operator calls;
        #   nil leaves evaluation unbounded.
        # @return [void]
        # @raise [DI::Error::EvaluationTimeout] the deadline has been exceeded.
        def raise_if_evaluation_deadline_exceeded(item_index, deadline)
          if item_index % EVALUATION_DEADLINE_CHECK_INTERVAL == 0 &&
              self.class.evaluation_deadline_exceeded?(deadline)
            raise DI::Error::EvaluationTimeout, EVALUATION_TIMEOUT_MESSAGE
          end
        end
        private :raise_if_evaluation_deadline_exceeded

        # Resolves a per-invocation thread-CPU-time deadline (float seconds)
        # for evaluating a probe condition, capture expression, or template
        # segment, from the configured evaluation timeout setting. Returns
        # nil when no evaluation timeout is configured, leaving evaluation
        # unbounded.
        #
        # @param settings [Datadog::Core::Configuration::Settings] settings to
        #   read the evaluation timeout budget from.
        # @return [Float, nil] the deadline, or nil when no timeout is configured.
        def self.evaluation_deadline(settings)
          budget_ms = settings.dynamic_instrumentation.max_time_to_evaluate_ms
          return nil unless budget_ms
          ::Process.clock_gettime(::Process::CLOCK_THREAD_CPUTIME_ID, :float_second) + budget_ms / 1000.0
        end

        # Returns whether the thread CPU clock has passed +deadline+.
        #
        # @param deadline [Float, nil] the deadline to check; nil means no
        #   deadline is set, leaving evaluation unbounded.
        # @return [Boolean] whether the deadline has been exceeded.
        def self.evaluation_deadline_exceeded?(deadline)
          !deadline.nil? && ::Process.clock_gettime(::Process::CLOCK_THREAD_CPUTIME_ID, :float_second) >= deadline
        end

        # Resolves the value of the local variable or argument +var+ from
        # the evaluation +context+.
        #
        # @param context [Context] context holding the evaluation locals.
        # @param var [Symbol, String] name of the local variable or argument.
        # @return [Object] value of the local variable or argument.
        def ref(context, var)
          context.fetch(var)
        end

        # Resolves the value of the instance variable +var+ from the
        # receiver of the evaluation +context+.
        #
        # @param context [Context] context holding the evaluation receiver.
        # @param var [Symbol, String] name of the instance variable.
        # @return [Object] value of the instance variable.
        def iref(context, var)
          context.fetch_ivar(var)
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

        # Returns true when +block+ returns a truthy value for every element
        # of +collection+.
        #
        # @param collection [Array, Hash] collection to test.
        # @param deadline [Float, nil] invocation-local evaluation deadline;
        #   nil leaves evaluation unbounded.
        # @return [Boolean] whether the block is satisfied by every element.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def all(collection, deadline, &block)
          case collection
          when Array
            i = 0
            collection.all? do |item|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              block.call(item)
            end
          when Hash
            i = 0
            collection.all? do |key, value|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              # For hashes, the expression language has both @it and
              # @key/@value. Manufacture @it from the key and value.
              block.call([key, value], key, value)
            end
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for all: #{collection.class}"
          end
        end

        # Returns true when +block+ returns a truthy value for any element
        # of +collection+.
        #
        # @param collection [Array, Hash] collection to test.
        # @param deadline [Float, nil] invocation-local evaluation deadline;
        #   nil leaves evaluation unbounded.
        # @return [Boolean] whether the block is satisfied by any element.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def any(collection, deadline, &block)
          case collection
          when Array
            i = 0
            collection.any? do |item|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              block.call(item)
            end
          when Hash
            i = 0
            collection.any? do |key, value|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              # For hashes, the expression language has both @it and
              # @key/@value. Manufacture @it from the key and value.
              block.call([key, value], key, value)
            end
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for any: #{collection.class}"
          end
        end

        # Returns the key-value pairs of the Hash +collection+ for which
        # +block+ returns a truthy value.
        #
        # Ruby 3.1 changed Hash#select to reuse the stored key hashes
        # instead of invoking the keys' hash methods and to keep a
        # compare_by_identity hash's distinct-but-eql? keys and identity
        # flag. Earlier Rubies invoke the keys' hash methods and collapse
        # identity hashes, so they keep the manual iteration, whose
        # built-in Hash#each is bound per invocation as ARRAY_EACH is.
        if Datadog::RubyVersion.is?(">= 3.1")
          def filter_hash(collection, deadline, &block)
            i = 0
            collection.select do |key, value|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              block.call([key, value], key, value)
            end.to_h
          end
        else
          # Built-in Hash#each and the core identity-mode check, resolved
          # once at load and bound per invocation so that #filter dispatches
          # no customer each or compare_by_identity? override during probe
          # evaluation.
          HASH_EACH = Hash.instance_method(:each)
          IDENTITY_MODE_CHECK = Hash.instance_method(:compare_by_identity?)
          private_constant :HASH_EACH, :IDENTITY_MODE_CHECK

          def filter_hash(collection, deadline, &block)
            i = 0
            result = {}
            result.compare_by_identity if IDENTITY_MODE_CHECK.bind(collection).call
            HASH_EACH.bind(collection).call do |key, value|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              result[key] = value if block.call([key, value], key, value)
            end
            result
          end
        end
        private :filter_hash

        # Returns the elements of +collection+ for which +block+ returns a
        # truthy value: the selected items of an Array collection, and a
        # Hash of the selected key-value pairs of a Hash collection.
        #
        # @param collection [Array, Hash] collection to filter.
        # @param deadline [Float, nil] invocation-local evaluation deadline;
        #   nil leaves evaluation unbounded.
        # @return [Array, Hash] the selected elements.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def filter(collection, deadline, &block)
          case collection
          when Array
            i = 0
            result = []
            ARRAY_EACH.bind(collection).call do |item|
              raise_if_evaluation_deadline_exceeded(i, deadline)
              i += 1
              result << item if block.call(item)
            end
            result
          when Hash
            filter_hash(collection, deadline, &block)
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
