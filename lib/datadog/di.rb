# frozen_string_literal: true

require_relative 'di/configuration'
require_relative 'di/extensions'
require_relative 'di/remote'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI
    INSTRUMENTED_COUNTERS_LOCK = Mutex.new

    # Captured at load time from Exception itself (not a subclass).
    # Used to bypass subclass overrides of backtrace_locations.
    #
    # This does NOT protect against monkeypatching Exception#backtrace_locations
    # before dd-trace-rb loads — in that case we'd capture the monkeypatch.
    # The practical threat model is customer subclasses overriding the method:
    #
    #   class MyError < StandardError
    #     def backtrace_locations; []; end
    #   end
    #
    # The UnboundMethod bypasses subclass overrides: bind(exception).call
    # always dispatches to the original Exception implementation.
    #
    # Note: if the subclass overrides #backtrace (not #backtrace_locations),
    # MRI's setup_exception skips storing the VM backtrace entirely — both
    # @bt and @bt_locations stay nil. In that case this UnboundMethod also
    # returns nil. See EXCEPTION_BACKTRACE comment and
    # docs/ruby/exception-backtrace-internals.md in claude-projects for the
    # full MRI analysis.
    EXCEPTION_BACKTRACE_LOCATIONS = Exception.instance_method(:backtrace_locations)

    # Same UnboundMethod trick for Exception#backtrace (Array<String>).
    # Used as a fallback when backtrace_locations returns nil — which happens
    # when someone calls Exception#set_backtrace with an Array<String>.
    #
    # set_backtrace accepts Array<String> or nil. When called with strings,
    # it replaces the VM-level backtrace: backtrace returns the new strings,
    # but backtrace_locations returns nil because the VM cannot reconstruct
    # Location objects from formatted strings. This occurs in exception
    # wrapping patterns where a library catches an exception, creates a new
    # one, and copies the original's string backtrace onto it via
    # set_backtrace before re-raising.
    #
    # Ruby 3.4+ also allows set_backtrace(Array<Location>), which preserves
    # backtrace_locations — but older Rubies and most existing code use
    # the string form.
    #
    # LIMITATION: Unlike EXCEPTION_BACKTRACE_LOCATIONS, this UnboundMethod
    # does NOT bypass subclass overrides of #backtrace. When a subclass
    # overrides #backtrace, MRI's setup_exception (eval.c) calls the
    # override via rb_get_backtrace, gets a non-nil result, and skips
    # storing the real VM backtrace in @bt and @bt_locations entirely.
    # The C function exc_backtrace then reads @bt (still nil from
    # exc_init) and returns nil.
    #
    # By contrast, setup_exception only checks for #backtrace overrides,
    # not #backtrace_locations overrides. So when only backtrace_locations
    # is overridden, the real backtrace IS stored, and the UnboundMethod
    # for backtrace_locations reads it directly from @bt_locations.
    #
    # This limitation is acceptable because this constant is only used as
    # a fallback when backtrace_locations returns nil. In the common
    # set_backtrace-with-strings case, no subclass override is involved
    # and the fallback works. If a subclass does override #backtrace AND
    # set_backtrace was called, set_backtrace writes to @bt via C
    # regardless of overrides, so the fallback still works.
    #
    # The only unrecoverable case: a subclass overrides #backtrace, the
    # exception is raised normally, and set_backtrace is never called.
    # Both @bt and @bt_locations are nil — the real backtrace was never
    # stored by raise. DI reports an empty stacktrace (type and message
    # are still reported).
    EXCEPTION_BACKTRACE = Exception.instance_method(:backtrace)

    class << self
      def enabled?
        Datadog.configuration.dynamic_instrumentation.enabled
      end

      # Returns iseqs that correspond to loaded files (filtering out eval'd code).
      #
      # There are several types of iseqs returned by +all_iseqs+:
      #
      # 1. Eval'd code — these have a nil +absolute_path+ and are filtered out here.
      # 2. Whole-file iseqs — have +absolute_path+ set and +first_lineno+ of 0.
      #    Only available for a subset of loaded files (the full-file iseq may be
      #    garbage collected after loading completes). Easiest to work with since
      #    we just match the file path to the probe specification.
      # 3. Per-method iseqs — have +absolute_path+ set and +first_lineno+ > 0.
      #    Often the only iseqs available for third-party code. Require identifying
      #    the correct iseq containing the target line, which may involve examining
      #    the iseq's +trace_points+ since +define_method+ can create nested,
      #    non-contiguous line ranges.
      #
      # Note: the same line of code can appear in multiple iseqs (e.g. when
      # +define_method+ is used inside a method). DI treats this as an error
      # since a probe must resolve to exactly one code location.
      #
      # @return [Array<RubyVM::InstructionSequence>] iseqs with non-nil +absolute_path+
      def file_iseqs
        all_iseqs.select do |iseq|
          iseq.absolute_path
        end
      end

      # This method is called from DI Remote handler to issue DI operations
      # to the probe manager (add or remove probes).
      #
      # When DI Remote is executing, Datadog.components should be initialized
      # and we should be able to reference it to get to the DI component.
      #
      # Given that we need the current_component anyway for code tracker,
      # perhaps we should delete the +component+ method and just use
      # +current_component+ in all cases.
      def component
        Datadog.send(:components).dynamic_instrumentation
      end

      # Track how many outstanding instrumentations are in DI.
      #
      # It is hard to find the actual instrumentations - there is no
      # method provided by Ruby to list all trace points, and we would
      # need to manually track our instrumentation modules for method probes.
      # Plus, tracking the modules could create active references to
      # instrumentation, which is not desired.
      #
      # A simpler solution is to maintain a counter which is increased
      # whenever a probe is installed and decreased when a probe is removed.
      #
      # This counter does not include pending probes - being not installed,
      # those pose no concerns to customer applications.
      def instrumented_count(kind = nil)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          if defined?(@instrumented_count)
            if kind
              validate_kind!(kind)
              @instrumented_count[kind] || 0
            else
              @instrumented_count.inject(0) do |sum, (_kind, count)|
                sum + count
              end
            end
          else
            0
          end
        end
      end

      def instrumented_count_inc(kind)
        validate_kind!(kind)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          @instrumented_count = Hash.new(0) unless defined?(@instrumented_count)
          @instrumented_count[kind] += 1
        end
      end

      def instrumented_count_dec(kind)
        validate_kind!(kind)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          @instrumented_count = Hash.new(0) unless defined?(@instrumented_count)
          if @instrumented_count[kind] <= 0
            Datadog.logger.debug { "di: attempting to decrease instrumented count below zero for #{kind}" }
            return
          end
          @instrumented_count[kind] -= 1
        end
      end

      private def validate_kind!(kind)
        unless %i[line method].include?(kind)
          raise ArgumentError, "Invalid kind: #{kind}"
        end
      end
    end

    # Expose DI to global shared objects
    Extensions.activate!
  end
end
