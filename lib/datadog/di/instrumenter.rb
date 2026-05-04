# frozen_string_literal: true

require_relative '../core/utils/time'

# rubocop:disable Lint/AssignmentInCondition
# rubocop:disable Style/AndOr

module Datadog
  module DI
    # Arranges to invoke a callback when a particular Ruby method or
    # line of code is executed.
    #
    # Method instrumentation is accomplished via module prepending.
    # Unlike the alias_method_chain pattern, module prepending permits
    # removing instrumentation with no virtually performance side-effects
    # (the target class retains an empty included module, but no additional
    # code is executed as part of target method).
    #
    # Method hooking works with explicitly defined methods and "virtual"
    # methods defined via method_missing.
    #
    # Line instrumentation is normally accomplished with a targeted line
    # trace point. This requires MRI and at least Ruby 2.6.
    # For testing purposes, it is also possible to use untargeted trace
    # points, but they have a huge performance penalty and should generally
    # not be used in production.
    #
    # Targeted line trace points require tracking of loaded code; see
    # the CodeTracker class for more details.
    #
    # Instrumentation state (i.e., the module or trace point used for
    # instrumentation) is stored in the Probe instance. Thus, Instrumenter
    # mutates attributes of Probes it is asked to install or remove.
    # A previous version of the code attempted to maintain the instrumentation
    # state within Instrumenter but this was very messy and hard to
    # guarantee correctness of. With the state stored in Probes, it is
    # straightforward to determine if a Probe has been successfully instrumented,
    # and thus requires cleanup, and to properly clean it up.
    #
    # Note that the upstream code is responsible for generally storing Probes.
    # This is normally accomplished by ProbeManager. ProbeManager stores all
    # known probes, instrumented or not, and is responsible for calling
    # +unhook+ of Instrumenter to clean up instrumentation when a user
    # deletes a probe in UI or when DI is shut down.
    #
    # Given the need to store state, and also that there are several Probe
    # attributes that affect how instrumentation is set up and that must be
    # consulted very early in the callback invocation (e.g., to perform
    # rate limiting correctly), Instrumenter takes Probe instances as
    # arguments rather than e.g. file + line number or class + method name.
    # As a result, Instrumenter is rather coupled to DI the product and is
    # not trivially usable as a general-purpose Ruby instrumentation tool
    # (however, Probe instances can be replaced by OpenStruct instances
    # providing the same interface with not much effort).
    #
    # Instrumenter (this class) is responsible for building snapshots.
    # This is because to capture values on method entry, those values need to
    # be duplicated or serialized into immutable values to prevent their
    # modification by the instrumented method. Therefore this class must
    # do at least some serialization/snapshot building and to keep the code
    # well-encapsulated, all serialization/snapshot building should thus be
    # initiated from this class rather than downstream code.
    #
    # As a consequence of Instrumenter building snapshots, it should not
    # expose TracePoint objects to any downstream code.
    #
    # @api private
    class Instrumenter
      def initialize(settings, serializer, logger, code_tracker: nil, telemetry: nil)
        @settings = settings
        @serializer = serializer
        @logger = logger
        @telemetry = telemetry
        @code_tracker = code_tracker

        @lock = Mutex.new
      end

      attr_reader :settings
      attr_reader :serializer
      attr_reader :logger
      attr_reader :telemetry
      attr_reader :code_tracker

      # This is a substitute for Thread::Backtrace::Location
      # which does not have a public constructor.
      # Used for the fabricated stack frame for the method itself
      # for method probes (which use Module#prepend and thus aren't called
      # from the method but from outside of the method).
      Location = Struct.new(:path, :lineno, :label)

      # Method probes can only target instance methods. The implementation uses
      # Module#prepend with a module that defines an instance method matching the
      # probe's target — class/singleton methods (def self.foo, module_function)
      # are not reachable via prepend on the class itself. Line probes are
      # unaffected since they install via TracePoint, not method dispatch.
      def hook_method(probe, responder)
        lock.synchronize do
          if probe.instrumentation_module
            # Already instrumented, warn?
            return
          end
        end

        cls = symbolize_class_name(probe.type_name)
        serializer = self.serializer
        method_name = probe.method_name
        loc = begin
          cls.instance_method(method_name).source_location
        rescue NameError
          # The target method is not defined.
          # This could be because it will be explicitly defined later
          # (since classes can be reopened in Ruby)
          # or the method is virtual (provided by a method_missing handler).
          # In these cases we do not have a source location for the
          # target method here.
        end
        rate_limiter = probe.rate_limiter
        settings = self.settings
        instrumenter = self

        mod = Module.new do
          define_method(method_name) do |*args, **kwargs, &target_block| # steep:ignore NoMethod
            # Re-entrancy guard: if we are already inside a DI probe
            # callback, skip DI processing and call the original method
            # directly. This prevents SystemStackError when a probe is
            # set on a stdlib method that DI itself calls during
            # snapshot building (e.g., String#length, Hash#each).
            #
            # Nested invocations during DI processing bypass the rate
            # limiter entirely — they are not user-observable probe
            # firings, just internal calls that happen to land on a
            # probed method, so they must not consume rate limit tokens.
            #
            # Storage is fiber-local. The DI.in_probe?/enter_probe/leave_probe
            # methods are implemented in C and access the storage directly via
            # rb_thread_local_aref / rb_thread_local_aset, bypassing Thread#[]
            # / Thread#[]= method dispatch — so user method probes on those
            # Thread methods cannot intercept guard reads/writes and recurse.
            if DI.in_probe?
              if !DI.array_empty?(args)
                if !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                  return super(*args, **kwargs, &target_block) # steep:ignore FallbackAny
                else
                  return super(*args, &target_block)
                end
              elsif !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                return super(**kwargs, &target_block) # steep:ignore FallbackAny
              else
                return super(&target_block)
              end
            end

            begin
            DI.enter_probe # rubocop:disable Layout/IndentationWidth

            # Steep cannot detect the type of **kwargs inside define_method blocks
            # (Ruby::FallbackAny). All kwargs references below are annotated with
            # steep:ignore FallbackAny.
            di_start_time = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

            if continue = probe.enabled?
              if condition = probe.condition
                begin
                  # This context will be recreated later, unlike for line probes.
                  #
                  # We do not need the stack for condition evaluation, therefore
                  # stack is not passed to Context here.
                  context = Context.new(
                    locals: serializer.combine_args(args, kwargs, self), # steep:ignore FallbackAny
                    target_self: self,
                    probe: probe, settings: settings, serializer: serializer,
                  )
                  continue = condition.satisfied?(context)
                rescue => exc
                  # Evaluation error exception can be raised for "expected"
                  # errors, we probably need another setting to control whether
                  # these exceptions are propagated.
                  raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions &&
                    !exc.is_a?(DI::Error::ExpressionEvaluationError)

                  if context
                    # We want to report evaluation errors for conditions
                    # as probe snapshots. However, if we failed to create
                    # the context, we won't be able to report anything as
                    # the probe notifier builder requires a context.
                    begin
                      responder.probe_condition_evaluation_failed_callback(context, exc)
                    rescue => nested_exc
                      raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                      instrumenter.logger.debug { "di: error in probe condition evaluation failed callback: #{nested_exc.class}: #{nested_exc.message}" }
                      instrumenter.telemetry&.report(nested_exc, description: "Error in probe condition evaluation failed callback")
                    end
                  else
                    _ = 42 # stop standard from wrecking this code

                    raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                    instrumenter.logger.debug { "di: error evaluating condition without context (tracer bug?): #{exc.class}: #{exc.message}" }
                    instrumenter.telemetry&.report(exc, description: "Error evaluating condition without context")
                    # If execution gets here, there is probably a bug in the tracer.
                  end

                  continue = false
                end
              end
            end

            if continue and rate_limiter.nil? || rate_limiter.allow?
              # Arguments may be mutated by the method, therefore
              # they need to be serialized prior to method invocation.
              serialized_entry_args = if probe.capture_snapshot?
                serializer.serialize_args(args, kwargs, self, # steep:ignore FallbackAny
                  depth: probe.max_capture_depth || settings.dynamic_instrumentation.max_capture_depth,
                  attribute_count: probe.max_capture_attribute_count || settings.dynamic_instrumentation.max_capture_attribute_count)
              end
              # We intentionally do not use Core::Utils::Time.get_time
              # here because the time provider may be overridden by the
              # customer, and DI is not allowed to invoke customer code.
              start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              di_duration = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - di_start_time

              # Release re-entrancy guard for the original method so that
              # probes on other methods (or recursive calls) fire normally
              # during user code execution.
              DI.leave_probe

              rv = nil
              begin
                # Under Ruby 2.6 we cannot just call super(*args, **kwargs)
                # for methods defined via method_missing.
                rv = if !DI.array_empty?(args)
                  if !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                    super(*args, **kwargs, &target_block) # steep:ignore FallbackAny
                  else
                    super(*args, &target_block)
                  end
                elsif !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                  super(**kwargs, &target_block) # steep:ignore FallbackAny
                else
                  super(&target_block)
                end
              rescue NoMemoryError, Interrupt, SystemExit
                raise
              rescue Exception => exc # standard:disable Lint/RescueException
                # We will raise the exception captured here later, after
                # the instrumentation callback runs.
              end

              # Re-acquire re-entrancy guard for DI post-processing
              # (building context, notification callback).
              DI.enter_probe

              end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              duration = end_time - start_time

              # Restart DI timer.
              # The DI execution duration covers time spent in DI code before
              # the customer method is invoked and time spent in DI code
              # after the customer method finishes.
              di_start_time = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

              # The method itself is not part of the stack trace because
              # we are getting the stack trace from outside of the method.
              # Add the method in manually as the top frame.
              method_frame = if loc
                [Location.new(loc.first, loc.last, method_name)]
              else
                # For virtual and lazily-defined methods, we do not have
                # the original source location here, and they won't be
                # included in the stack trace currently.
                # TODO when begin/end trace points are added for local
                # variable capture in method probes, we should be able
                # to obtain actual method execution location and use
                # that location here.
                []
              end
              caller_locs = method_frame + caller_locations
              # TODO capture arguments at exit

              context = Context.new(locals: nil, target_self: self,
                probe: probe, settings: settings, serializer: serializer,
                serialized_entry_args: serialized_entry_args,
                caller_locations: caller_locs,
                return_value: rv, duration: duration, exception: exc,)

              begin
                responder.probe_executed_callback(context)

                instrumenter.send(:check_and_disable_if_exceeded, probe, responder, di_start_time, di_duration)
              rescue => di_exc
                raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                instrumenter.logger.debug { "di: unhandled exception in method probe: #{di_exc.class}: #{di_exc.message}" }
                instrumenter.telemetry&.report(di_exc, description: "Unhandled exception in method probe")
              end

              if exc
                raise exc
              else
                rv
              end
            else
              # stop standard from trying to mess up my code
              _ = 42

              # Release re-entrancy guard for the original method.
              DI.leave_probe

              # The necessity to invoke super in each of these specific
              # ways is very difficult to test.
              # Existing tests, even though I wrote many, still don't
              # cause a failure if I replace all of the below with a
              # simple super(*args, **kwargs, &target_block).
              # But, let's be safe and go through the motions in case
              # there is actually a legitimate need for the breakdown.
              # TODO figure out how to test this properly.
              if !DI.array_empty?(args)
                if !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                  super(*args, **kwargs, &target_block) # steep:ignore FallbackAny
                else
                  super(*args, &target_block)
                end
              elsif !DI.hash_empty?(kwargs) # steep:ignore FallbackAny
                super(**kwargs, &target_block) # steep:ignore FallbackAny
              else
                super(&target_block)
              end
            end
            ensure
              DI.leave_probe # rubocop:disable Layout/IndentationWidth
            end
          end
        end

        lock.synchronize do
          if probe.instrumentation_module
            # Already instrumented from another thread
            return
          end

          probe.instrumentation_module = mod
          cls.send(:prepend, mod)

          DI.instrumented_count_inc(:method)
        end
      end

      def unhook_method(probe)
        # Ruby does not permit removing modules from classes.
        # We can, however, remove method definitions from modules.
        # After this the modules remain in memory and stay included
        # in the classes but are empty (have no methods).
        lock.synchronize do
          if mod = probe.instrumentation_module
            mod.send(:remove_method, probe.method_name)
            probe.instrumentation_module = nil

            DI.instrumented_count_dec(:method)
          end
        end
      end

      # Instruments a particluar line in a source file.
      # Note that this method only works for physical files,
      # not for eval'd code, unless the eval'd code is associated with
      # a file name and client invokes this method with the correct
      # file name for the eval'd code.
      def hook_line(probe, responder)
        lock.synchronize do
          if probe.instrumentation_trace_point
            # Already instrumented, warn?
            return
          end
        end

        line_no = probe.line_no!

        # Memoize the value to ensure this method always uses the same
        # value for the setting.
        # Normally none of the settings should change, but in the test suite
        # we use mock objects and the methods may be mocked with
        # individual invocations, yielding different return values on
        # different calls to the same method.
        permit_untargeted_trace_points = settings.dynamic_instrumentation.internal.untargeted_trace_points

        iseq = nil
        if code_tracker
          # Steep: Complex type narrowing (before calling hook_line,
          # we check that probe.line? is true which itself checks that probe.file is not nil)
          # Annotation do not work here as `file` is a method on probe, not a local variable.
          ret = if code_tracker.respond_to?(:iseq_for_line)
            code_tracker.iseq_for_line(probe.file, line_no) # steep:ignore ArgumentTypeMismatch
          else
            code_tracker.iseqs_for_path_suffix(probe.file) # steep:ignore ArgumentTypeMismatch
          end
          unless ret
            if permit_untargeted_trace_points
              # Continue withoout targeting the trace point.
              # This is going to cause a serious performance penalty for
              # the entire file containing the line to be instrumented.
            else
              # Do not use untargeted trace points unless they have been
              # explicitly requested by the user, since they cause a
              # serious performance penalty.
              #
              # If the requested file is not in code tracker's registry,
              # or the code tracker does not exist at all,
              # do not attempt to instrument now.
              # The caller should add the line to the list of pending lines
              # to instrument and install the hook when the file in
              # question is loaded (and hopefully, by then code tracking
              # is active, otherwise the line will never be instrumented.)
              raise_if_probe_in_loaded_features(probe, line_no, code_tracker)
              raise Error::DITargetNotDefined, "File not in code tracker registry: #{probe.file}:#{line_no}"
            end
          end
        elsif !permit_untargeted_trace_points
          # Same as previous comment, if untargeted trace points are not
          # explicitly defined, and we do not have code tracking, do not
          # instrument the method.
          raise_if_probe_in_loaded_features(probe, line_no, nil)
          raise Error::DITargetNotDefined, "File not in code tracker registry: #{probe.file}:#{line_no}"
        end

        if ret
          actual_path, iseq = ret
        end

        # If trace point is not targeted, we only need one trace point per file.
        # Creating a trace point for each probe does work but the performance
        # penalty will be taken for each trace point defined in the file.
        # Since untargeted trace points are only (currently) used internally
        # for benchmarking, and shouldn't be used in customer applications,
        # we always create a trace point here to reduce complexity.
        #
        # For targeted trace points, if multiple probes target the same
        # file and line, we also only need one trace point, but since the
        # overhead of targeted trace points is minimal, don't worry about
        # this optimization just yet and create a trace point for each probe.

        types = if iseq
          # When targeting trace points we can target the 'end' line of a method.
          # However, by adding the :return trace point we lose diagnostics
          # for lines that contain no executable code (e.g. comments only)
          # and thus cannot actually be instrumented.
          [:line, :return, :b_return]
        else
          [:line]
        end
        tp = TracePoint.new(*types) do |tp|
          line_trace_point_callback(probe, iseq, responder, tp)
        end

        # Internal sanity check - untargeted trace points create a huge
        # performance impact, and we absolutely do not want to set them
        # accidentally.
        if !iseq && !permit_untargeted_trace_points
          raise Error::InternalError, "Trying to use an untargeted trace point when user did not permit it"
        end

        lock.synchronize do
          if probe.instrumentation_trace_point
            # Already instrumented in another thread, warn?
            return
          end

          probe.instrumentation_trace_point = tp
          # actual_path could be nil if we don't use targeted trace points.
          probe.instrumented_path = actual_path

          # TracePoint#enable returns false when it succeeds.
          rv = if iseq
            tp.enable(target: iseq, target_line: line_no)
          else
            tp.enable
          end

          DI.instrumented_count_inc(:line)

          rv
        end
        true
      end

      def unhook_line(probe)
        lock.synchronize do
          if tp = probe.instrumentation_trace_point
            tp.disable
            probe.instrumentation_trace_point = nil

            DI.instrumented_count_dec(:line)
          end
        end
      end

      def hook(probe, responder)
        if probe.method?
          hook_method(probe, responder)
        elsif probe.line?
          hook_line(probe, responder)
        else
          # TODO add test coverage for this path
          logger.debug { "di: unknown probe type to hook: #{probe}" }
        end
      end

      def unhook(probe)
        if probe.method?
          unhook_method(probe)
        elsif probe.line?
          unhook_line(probe)
        else
          # TODO add test coverage for this path
          logger.debug { "di: unknown probe type to unhook: #{probe}" }
        end
      end

      class << self
        def get_local_variables(trace_point)
          # binding appears to be constructed on access, therefore
          # 1) we should attempt to cache it and
          # 2) we should not call +binding+ until we actually need variable values.
          binding = trace_point.binding

          # steep hack - should never happen
          return {} unless binding

          binding.local_variables.each_with_object({}) do |name, map|
            value = binding.local_variable_get(name)
            map[name] = value
          end
        end
      end

      private

      attr_reader :lock

      def line_trace_point_callback(probe, iseq, responder, tp)
        di_start_time = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

        # Check if probe is enabled before doing any processing
        return unless probe.enabled?

        # If trace point is not targeted, we must verify that the invocation
        # is the file & line that we want, because untargeted trace points
        # are invoked for *each* line of Ruby executed.
        # TODO find out exactly when the path in trace point is relative.
        # Looks like this is the case when line trace point is not targeted?
        unless iseq
          return unless tp.lineno == probe.line_no && ( # standard:disable Style/UnlessLogicalOperators
            probe.file == tp.path || probe.file_matches?(tp.path)
          )
        end

        # We set the trace point on :return to be able to instrument
        # 'end' lines. This also causes the trace point to be invoked on
        # non-'end' lines when a line raises an exception, since the
        # exception causes the method to stop executing and stack unwends.
        # We do not want two invocations of the trace point.
        # Therefore, if a trace point is invoked with a :line event,
        # mark it as such and ignore subsequent :return events.
        if probe.executed_on_line?
          return unless tp.event == :line
        else
          _ = 42 # stop standard from changing this code

          if tp.event == :line
            probe.executed_on_line!
          end
        end

        if condition = probe.condition
          begin
            context = build_trace_point_context(probe, tp)
            return unless condition.satisfied?(context)
          rescue => exc
            # Evaluation error exception can be raised for "expected"
            # errors, we probably need another setting to control whether
            # these exceptions are propagated.
            raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions &&
              !exc.is_a?(DI::Error::ExpressionEvaluationError)

            if context
              # We want to report evaluation errors for conditions
              # as probe snapshots. However, if we failed to create
              # the context, we won't be able to report anything as
              # the probe notifier builder requires a context.
              begin
                responder.probe_condition_evaluation_failed_callback(context, condition, exc)
              rescue => nested_exc
                raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

                logger.debug { "di: error in probe condition evaluation failed callback: #{nested_exc.class}: #{nested_exc.message}" }
                telemetry&.report(nested_exc, description: "Error in probe condition evaluation failed callback")
              end

              return
            else
              _ = 42 # stop standard from wrecking this code

              raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions

              logger.debug { "di: error evaluating condition without context (tracer bug?): #{exc.class}: #{exc.message}" }
              telemetry&.report(exc, description: "Error evaluating condition without context")
              # If execution gets here, there is probably a bug in the tracer.
            end
          end
        end

        # In practice we should always have a rate limiter, but be safe
        # and check that it is in fact set.
        return if probe.rate_limiter && !probe.rate_limiter.allow?

        # The context creation is relatively expensive and we don't
        # want to run it if the callback won't be executed due to the
        # rate limit.
        # Thus the copy-paste of the creation call here.
        context ||= build_trace_point_context(probe, tp)

        responder.probe_executed_callback(context)

        check_and_disable_if_exceeded(probe, responder, di_start_time)
      rescue => exc
        raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
        logger.debug { "di: unhandled exception in line trace point: #{exc.class}: #{exc.message}" }
        telemetry&.report(exc, description: "Unhandled exception in line trace point")
        # TODO test this path
      end

      def build_trace_point_context(probe, tp)
        stack = caller_locations
        # We have two helper methods being invoked from the trace point
        # handler block, remove them from the stack.
        #
        # According to steep stack may be nil.
        stack&.shift(2)
        Context.new(
          locals: Instrumenter.get_local_variables(tp),
          target_self: tp.self,
          probe: probe,
          settings: settings,
          serializer: serializer,
          path: tp.path,
          caller_locations: stack,
        )
      end

      # Circuit breaker: disables the probe if total CPU time consumed by
      # DI processing exceeds the configured threshold.
      def check_and_disable_if_exceeded(probe, responder, di_start_time, accumulated_duration = 0.0)
        return unless max_processing_time = settings.dynamic_instrumentation.internal.max_processing_time

        di_duration = accumulated_duration + Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - di_start_time
        if di_duration > max_processing_time
          logger.debug { "di: disabling probe: consumed #{di_duration}: #{probe}" }
          # We disable the probe here rather than remove it to
          # avoid a dependency on ProbeManager from Instrumenter.
          probe.disable!
          responder.probe_disabled_callback(probe, di_duration)
        end
      end

      def raise_if_probe_in_loaded_features(probe, line_no, code_tracker)
        return unless probe.file

        # Find the loaded path matching the probe file.
        loaded_path = if $LOADED_FEATURES.include?(probe.file)
          probe.file
        else
          # Expensive suffix check.
          $LOADED_FEATURES.find { |path| Utils.path_matches_suffix?(path, probe.file) }
        end

        return unless loaded_path

        # Distinguish between "no iseqs at all" and "has per-method iseqs
        # but none cover this line".
        has_per_method = code_tracker&.send(:instance_variable_defined?, :@per_method_registry) &&
          code_tracker.send(:per_method_registry).key?(loaded_path)

        if has_per_method
          raise Error::DITargetNotInRegistry,
            "File #{loaded_path} is loaded and has per-method iseqs, " \
            "but none cover line #{line_no}. " \
            "The line may be in file-level setup code outside any method."
        else
          raise Error::DITargetNotInRegistry,
            "File #{loaded_path} is loaded but has no surviving iseqs " \
            "(whole-file iseq was garbage collected and no per-method iseqs remain). " \
            "Line probes cannot target this file."
        end
      end

      # TODO test that this resolves qualified names e.g. A::B
      def symbolize_class_name(cls_name)
        Object.const_get(cls_name)
      rescue NameError => exc
        raise Error::DITargetNotDefined, "Class not defined: #{cls_name}: #{exc.class}: #{exc.message}"
      end
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
# rubocop:enable Style/AndOr
