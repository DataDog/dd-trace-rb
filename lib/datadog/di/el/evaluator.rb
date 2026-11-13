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
        # operator. Wall clock, while the evaluation budget is thread CPU
        # time: the regexp engine's `timeout:` keyword and Timeout.timeout
        # offer no CPU-time mode.
        MATCHES_TIMEOUT_SECONDS = 0.05

        MATCHES_TIMEOUT_MESSAGE = "matches operator timeout"

        # Number of collection items processed between cooperative
        # evaluation-deadline checks; evaluation aborts within one
        # interval's worth of items past the deadline. A `matches`
        # invocation can spend MATCHES_TIMEOUT_SECONDS of wall time, so
        # #matches and #matches_compiled check the deadline before each
        # match; a predicate that runs `matches` per item therefore
        # adds at most the one match in flight when the deadline
        # passes to the overshoot.
        EVALUATION_DEADLINE_CHECK_INTERVAL = 64

        # Built-in Array#each and Hash#each, resolved once at load and
        # bound per invocation: the collection operators' iteration then
        # dispatches no customer each override during probe evaluation.
        ARRAY_EACH = Array.instance_method(:each)
        HASH_EACH = Hash.instance_method(:each)
        private_constant :ARRAY_EACH, :HASH_EACH

        # @param regexps [Array<Regexp>] Regexps precompiled from literal
        #   `matches` patterns, looked up by index by #matches_compiled.
        #    Empty when the expression has no `matches` pattern with
        #    a direct regular expression argument.
        def initialize(regexps = [])
          @regexps = regexps
        end

        attr_reader :regexps

        # Raises DI::Error::EvaluationTimeout when the evaluation deadline
        # has been exceeded, aborting evaluation cooperatively.
        #
        # @param evaluation_deadline [Float] invocation-local evaluation
        #   deadline, passed from the compiled #evaluate into the operator
        #   calls.
        # @return [void]
        # @raise [DI::Error::EvaluationTimeout] the deadline has been exceeded.
        def raise_if_evaluation_deadline_exceeded(evaluation_deadline)
          if self.class.evaluation_deadline_exceeded?(evaluation_deadline)
            raise DI::Error::EvaluationTimeout
          end
        end
        private :raise_if_evaluation_deadline_exceeded

        # Raises DI::Error::EvaluationTimeout when +item_index+ falls on
        # a cooperative check boundary and the evaluation deadline has
        # been exceeded. The thread CPU clock is read only at every
        # EVALUATION_DEADLINE_CHECK_INTERVAL-th item, so an already-exceeded
        # deadline raises at the first boundary at or after it passes.
        #
        # @param item_index [Integer] zero-based index of the collection
        #   element being processed.
        # @param evaluation_deadline [Float] invocation-local evaluation
        #   deadline, passed from the compiled #evaluate into the operator
        #   calls.
        # @return [void]
        # @raise [DI::Error::EvaluationTimeout] a check boundary was reached
        #   with the deadline exceeded.
        def raise_if_deadline_check_due_and_exceeded(item_index, evaluation_deadline)
          if (item_index % EVALUATION_DEADLINE_CHECK_INTERVAL).zero?
            raise_if_evaluation_deadline_exceeded(evaluation_deadline)
          end
        end
        private :raise_if_deadline_check_due_and_exceeded

        # Yields the evaluation values for one collection element — the
        # item alone for an Array element, or the [key, value] pair as
        # @it together with the @key and the @value for a Hash element —
        # iterating through the built-in iteration methods bound per
        # invocation and performing the interval-gated evaluation-deadline
        # check and its counter advance between elements.
        #
        # @param collection [Array, Hash] collection whose elements the
        #   block receives.
        # @param evaluation_deadline [Float] invocation-local evaluation deadline.
        # @param operator_name [String] name of the invoking collection
        #   operator, reported in the bad-collection-type error.
        # @yield [current_item, current_key, current_value] evaluation
        #   values for one element.
        # @return [void]
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is
        #   not an Array or a Hash.
        def each_collection_item(collection, evaluation_deadline, operator_name)
          case collection
          when Array
            i = 0
            ARRAY_EACH.bind(collection).call do |item|
              raise_if_deadline_check_due_and_exceeded(i, evaluation_deadline)
              i += 1
              yield item, nil, nil
            end
          when Hash
            i = 0
            HASH_EACH.bind(collection).call do |key, value|
              raise_if_deadline_check_due_and_exceeded(i, evaluation_deadline)
              i += 1
              yield [key, value], key, value
            end
          else
            raise DI::Error::ExpressionEvaluationError, "Bad collection type for #{operator_name}: #{collection.class}"
          end
          nil
        end
        private :each_collection_item

        # Returns whether the thread CPU clock has passed +evaluation_deadline+.
        #
        # @param evaluation_deadline [Float] the deadline to check.
        # @return [Boolean] whether the deadline has been exceeded.
        def self.evaluation_deadline_exceeded?(evaluation_deadline)
          Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) >= evaluation_deadline
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
          if String === haystack && String === needle or # rubocop:disable Style/AndOr
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
        # @param evaluation_deadline [Float] invocation-local evaluation
        #   deadline.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded before the match started, or the match exceeded
        #   MATCHES_TIMEOUT_SECONDS.
        def matches(haystack, needle, evaluation_deadline)
          raise_if_evaluation_deadline_exceeded(evaluation_deadline)
          bounded_match?(Evaluator.compile_regexp(needle), haystack)
        end

        # Match +haystack+ against a Regexp precompiled at expression-compile
        # time, looked up by index in +regexps+.
        #
        # @param haystack [String] string to match against.
        # @param index [Integer] position of the precompiled Regexp in +regexps+.
        # @param evaluation_deadline [Float] invocation-local evaluation
        #   deadline.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded before the match started, or the match exceeded
        #   MATCHES_TIMEOUT_SECONDS.
        def matches_compiled(haystack, index, evaluation_deadline)
          raise_if_evaluation_deadline_exceeded(evaluation_deadline)
          bounded_match?(regexps.fetch(index), haystack)
        end

        # Match +haystack+ against +re+, bounded at MATCHES_TIMEOUT_SECONDS
        # wall-clock.
        #
        # @param re [Regexp] regexp to match against.
        # @param haystack [String] string to match against.
        # @return [Boolean] whether the haystack matches the regexp.
        # @raise [DI::Error::EvaluationTimeout] the match exceeded
        #   MATCHES_TIMEOUT_SECONDS.
        if Datadog::RubyVersion.is?(">= 3.2")
          def bounded_match?(re, haystack)
            # Uses Regexp#match? rather than =~ so that the
            # thread-local match data ($~, $1, ...) is not mutated as a side
            # effect of DI expression evaluation.
            re.match?(haystack)
          rescue Regexp::TimeoutError
            raise DI::Error::EvaluationTimeout.new(message: MATCHES_TIMEOUT_MESSAGE)
          end
        else
          # Raised by Timeout.timeout in the matching thread. A dedicated
          # class because Timeout.timeout passes a positional message,
          # which EvaluationTimeout does not accept, and because rescuing
          # Timeout::Error would also catch an enclosing customer timeout.
          class MatchTimeoutSignal < StandardError
          end
          private_constant :MatchTimeoutSignal

          def bounded_match?(re, haystack)
            Timeout.timeout(MATCHES_TIMEOUT_SECONDS, MatchTimeoutSignal) do
              re.match?(haystack)
            end
          rescue MatchTimeoutSignal
            raise DI::Error::EvaluationTimeout.new(message: MATCHES_TIMEOUT_MESSAGE)
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
        # @param evaluation_deadline [Float] invocation-local evaluation deadline.
        # @return [Boolean] whether the block is satisfied by every element.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def all(collection, evaluation_deadline, &block)
          result = true
          each_collection_item(collection, evaluation_deadline, "all") do |current_item, current_key, current_value|
            unless block.call(current_item, current_key, current_value)
              result = false
              break
            end
          end
          result
        end

        # Returns true when +block+ returns a truthy value for any element
        # of +collection+.
        #
        # @param collection [Array, Hash] collection to test.
        # @param evaluation_deadline [Float] invocation-local evaluation deadline.
        # @return [Boolean] whether the block is satisfied by any element.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def any(collection, evaluation_deadline, &block)
          result = false
          each_collection_item(collection, evaluation_deadline, "any") do |current_item, current_key, current_value|
            if block.call(current_item, current_key, current_value)
              result = true
              break
            end
          end
          result
        end

        # Returns the key-value pairs of the Hash +collection+ for which
        # +block+ returns a truthy value.
        #
        # Ruby 3.1 changed Hash#select to reuse the stored key hashes
        # instead of invoking the keys' hash methods and to keep a
        # compare_by_identity hash's distinct-but-eql? keys and identity
        # flag, so this Ruby filters through the built-in Hash#select
        # bound per invocation. Earlier Rubies invoke the keys' hash
        # methods and collapse identity hashes, so they keep the manual
        # iteration through #each_collection_item, preserving the source
        # hash's identity mode in the result.
        if Datadog::RubyVersion.is?(">= 3.1")
          # Built-in Hash#select, resolved once at load and bound per
          # invocation: #filter's Hash iteration then dispatches no
          # customer select override during probe evaluation.
          HASH_SELECT = Hash.instance_method(:select)
          private_constant :HASH_SELECT

          def filter_hash(collection, evaluation_deadline, &block)
            i = 0
            HASH_SELECT.bind(collection).call do |key, value|
              raise_if_deadline_check_due_and_exceeded(i, evaluation_deadline)
              i += 1
              block.call([key, value], key, value)
            end.to_h
          end
        else
          # Core identity-mode check, resolved once at load and bound per
          # invocation so that #filter dispatches no customer
          # compare_by_identity? override during probe evaluation.
          IDENTITY_MODE_CHECK = Hash.instance_method(:compare_by_identity?)
          private_constant :IDENTITY_MODE_CHECK

          def filter_hash(collection, evaluation_deadline, &block)
            result = {}
            result.compare_by_identity if IDENTITY_MODE_CHECK.bind(collection).call
            each_collection_item(collection, evaluation_deadline, "filter") do |_current_item, current_key, current_value|
              result[current_key] = current_value if block.call([current_key, current_value], current_key, current_value)
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
        # @param evaluation_deadline [Float] invocation-local evaluation deadline.
        # @return [Array, Hash] the selected elements.
        # @raise [DI::Error::EvaluationTimeout] the evaluation deadline was
        #   exceeded mid-iteration.
        # @raise [DI::Error::ExpressionEvaluationError] +collection+ is not
        #   an Array or a Hash.
        def filter(collection, evaluation_deadline, &block)
          case collection
          when Array
            result = []
            each_collection_item(collection, evaluation_deadline, "filter") do |current_item, current_key, current_value|
              result << current_item if block.call(current_item, current_key, current_value)
            end
            result
          when Hash
            filter_hash(collection, evaluation_deadline, &block)
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
            if supercls = cls.superclass # rubocop:disable Lint/AssignmentInCondition
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
