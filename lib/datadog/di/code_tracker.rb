# frozen_string_literal: true

# rubocop:disable Lint/AssignmentInCondition

require_relative 'error'

module Datadog
  module DI
    # Tracks loaded Ruby code by source file and maintains a map from
    # source file to the loaded code (instruction sequences).
    # Also arranges for code in the loaded files to be instrumented by
    # line probes that have already been received by the library.
    #
    # The loaded code is used to target line trace points when installing
    # line probes which dramatically improves efficiency of line trace points.
    #
    # Note that, since most files will only be loaded one time (via the
    # "require" mechanism), the code tracker needs to be global and not be
    # recreated when the DI component is created.
    #
    # @api private
    class CodeTracker
      def initialize
        @registry = {}
        @per_method_registry = {}
        @trace_point_lock = Mutex.new
        @registry_lock = Mutex.new
        @compiled_trace_point = nil
      end

      # Populates the registry with iseqs for files that were loaded
      # before code tracking started.
      #
      # Uses the all_iseqs C extension to walk the Ruby object space and
      # find instruction sequences for already-loaded code. Whole-file
      # iseqs are stored in the main registry; per-method/block/class
      # iseqs are stored in per_method_registry as fallback for files
      # whose whole-file iseq was GC'd.
      #
      # See docs/DynamicInstrumentationDevelopment.md "Iseq Lifecycle and GC"
      # for which iseq types survive GC and implications for backfill.
      #
      # Whole-file detection uses two strategies:
      # - Ruby 3.1+: DI.iseq_type (wraps rb_iseq_type) returns :top for
      #   require/load and :main for the entry script. This is precise.
      # - Ruby < 3.1: falls back to first_lineno == 0, which is true for
      #   whole-file iseqs from require/load (INT2FIX(0) in Ruby's
      #   rb_iseq_new_top and rb_iseq_new_main) and false for
      #   method/block/class definitions (first_lineno >= 1).
      #   InstructionSequence.compile passes first_lineno = 1 by default,
      #   so eval'd code is not matched. Both strategies produce the same
      #   result in practice.
      #
      # Does not overwrite iseqs already in the registry (from
      # :script_compiled), since those are guaranteed to be whole-file
      # iseqs and are authoritative.
      #
      # @return [void]
      def backfill_registry
        iseqs = DI.file_iseqs
        have_iseq_type = DI.respond_to?(:iseq_type)
        registry_lock.synchronize do
          iseqs.each do |iseq|
            path = iseq.absolute_path
            next unless path

            whole_file = if have_iseq_type
              type = DI.iseq_type(iseq)
              # Require first_lineno == 0 to exclude compile_file/compile
              # iseqs. These are :top type but have first_lineno == 1 and
              # produce iseq objects distinct from require-produced iseqs.
              # Targeted TracePoints are bound to the specific iseq object
              # — a probe on a compile_file iseq silently never fires when
              # the require-produced code runs.
              (type == :top || type == :main) && iseq.first_lineno == 0
            else
              iseq.first_lineno == 0
            end

            if whole_file
              # Do not overwrite entries from :script_compiled — those are
              # captured at load time and are authoritative.
              next if registry.key?(path)

              registry[path] = iseq
            else
              # Skip top-level script iseqs (:top/:main) produced by
              # RubyVM::InstructionSequence.compile_file and .compile
              # (compile source to bytecode without executing it).
              # These represent the file body,
              # not a method or block. They pass the first_lineno check
              # (lineno != 0) but a targeted TracePoint bound to one
              # of these never fires for method-level code — the
              # user's probe silently produces no snapshots.
              #
              # On Ruby < 3.1 (no iseq_type), we cannot distinguish
              # these from method iseqs, so they leak into
              # per_method_registry. If iseq_for_line selects a leaked
              # top-level iseq instead of the real method iseq, the
              # probe installs but silently never fires — same failure
              # as above. This requires the application to call
              # compile_file and hold the result, which is rare outside
              # tooling like bootsnap (which discards it).
              next if have_iseq_type && (type == :top || type == :main)

              # Store per-method/block/class iseqs as fallback for files
              # whose whole-file iseq was GC'd. These can be used to
              # target line probes on lines within their range.
              (per_method_registry[path] ||= []) << iseq
            end
          end
        end
        nil
      rescue => exc
        # Backfill is best-effort — if it fails, line probes on
        # pre-loaded code won't work but everything else is unaffected.
        if component = DI.current_component
          component.logger.debug { "di: backfill_registry failed: #{exc.class}: #{exc}" }
          component.telemetry&.report(exc, description: "backfill_registry failed")
        end
        nil
      end

      # Starts tracking loaded code.
      #
      # This method should generally be called early in application boot
      # process, because any code loaded before code tracking is enabled
      # will not be instrumentable via line probes.
      #
      # Normally tracking should remain active for the lifetime of the
      # process and would not be ever stopped.
      def start
        trace_point_lock.synchronize do
          # If this code tracker is already running, we can do nothing or
          # restart it (by disabling the trace point and recreating it).
          # It is likely that some applications will attempt to activate
          # DI more than once where the intention is to just activate DI;
          # do not break such applications by clearing out the registry.
          # For now, until there is a use case for recreating the trace point,
          # do nothing if the code tracker has already started.
          return if @compiled_trace_point

          # Note: .trace enables the trace point.
          @compiled_trace_point = TracePoint.trace(:script_compiled) do |tp|
            # Useful attributes of the trace point object here:
            # .instruction_sequence
            # .instruction_sequence.path (either absolute file path for
            #   loaded or required code, or for eval'd code, if filename
            #   is specified as argument to eval, then this is the provided
            #   filename, otherwise this is a synthesized
            #   "(eval at <definition-file>:<line>)" string)
            # .instruction_sequence.absolute_path (absolute file path when
            #   load or require are used to load code, nil for eval'd code
            #   regardless of whether filename was specified as an argument
            #   to eval on ruby 3.1+, same as path for eval'd code on ruby 3.0
            #   and lower)
            # .method_id
            # .path (refers to the code location that called the require/eval/etc.,
            #   not where the loaded code is; use .path on the instruction sequence
            #   to obtain the location of the compiled code)
            # .eval_script
            #
            # For now just map the path to the instruction sequence.
            path = tp.instruction_sequence.absolute_path
            # Do not store mapping for eval'd code, since there is no way
            # to target such code from dynamic instrumentation UI.
            # eval'd code always sets tp.eval_script.
            # When tp.eval_script is nil, code is either 'load'ed or 'require'd.
            # steep, of course, complains about indexing with +path+
            # without checking that it is not nil, so here, maybe there is
            # some situation where path would in fact be nil and
            # steep would end up saving the day.
            if path && !tp.eval_script
              registry_lock.synchronize do
                registry[path] = tp.instruction_sequence
              end

              # Also, pending line probes should only be installed for
              # non-eval'd code.
              DI.current_component&.probe_manager&.install_pending_line_probes(path)
            end
          # Since this method normally is called from customer applications,
          # rescue any exceptions that might not be handled to not break said
          # customer applications.
          rescue => exc
            # Code tracker may be loaded without the rest of DI,
            # in which case DI.component will not yet be defined,
            # but we will have DI.current_component (set to nil).
            if component = DI.current_component
              raise if component.settings.dynamic_instrumentation.internal.propagate_all_exceptions
              component.logger.debug { "di: unhandled exception in script_compiled trace point: #{exc.class}: #{exc}" }
              component.telemetry&.report(exc, description: "Unhandled exception in script_compiled trace point")
              # TODO test this path
            else
              # If we don't have a component, we cannot log anything properly.
              # Do not just print a warning to avoid spamming customer logs.
              # Don't reraise the exception either.
              # TODO test this path
            end
          end

          # Backfill the registry with iseqs for files that were loaded
          # before tracking started. This must happen after the trace
          # point is enabled so that any files loaded concurrently are
          # captured by the trace point (backfill won't overwrite them).
          backfill_registry
        end
      end

      # Returns whether this code tracker has been activated and is
      # tracking.
      def active?
        trace_point_lock.synchronize do
          !!@compiled_trace_point
        end
      end

      # Returns an array of RubVM::InstructionSequence (i.e. the compiled code)
      # for the provided path.
      #
      # The argument can be a full path to a Ruby source code file or a
      # suffix (basename + one or more directories preceding the basename).
      # The idea with suffix matches is that file paths are likely to
      # be different between development and production environments and
      # the source control system uses relative paths and doesn't have
      # absolute paths at all.
      #
      # Suffix matches are not guaranteed to be correct, meaning there may
      # be multiple files with the same basename and they may all match a
      # given suffix. In such cases, this method will return all matching
      # paths (and all of these paths will be attempted to be instrumented
      # by upstream code).
      #
      # If the suffix matches one of the paths completely (which requires it
      # to be an absolute path), only the exactly matching path is returned.
      # Otherwise all known paths that end in the suffix are returned.
      # If no paths match, an empty array is returned.
      def iseqs_for_path_suffix(suffix)
        registry_lock.synchronize do
          exact = registry[suffix]
          return [suffix, exact] if exact

          suffix = suffix.dup
          loop do
            inexact = []
            registry.each do |path, iseq|
              if Utils.path_matches_suffix?(path, suffix)
                inexact << [path, iseq]
              end
            end
            if inexact.length > 1
              raise Error::MultiplePathsMatch, "Multiple paths matched requested suffix"
            end
            if inexact.any?
              return inexact.first
            end
            return nil unless suffix.include?('/')
            suffix.sub!(%r{.*/+}, '')
          end
        end
      end

      # Returns a [path, iseq] pair for a line probe target, or nil.
      #
      # First checks the whole-file iseq registry (via iseqs_for_path_suffix).
      # If no whole-file iseq exists, searches the per-method iseq registry
      # for an iseq whose trace_points include the target line.
      #
      # @param suffix [String] file path or suffix to match
      # @param line [Integer] target line number
      # @return [Array(String, RubyVM::InstructionSequence), nil]
      def iseq_for_line(suffix, line)
        # Try whole-file iseq first — it always covers all lines.
        result = iseqs_for_path_suffix(suffix)
        return result if result

        # Fall back to per-method iseqs.
        registry_lock.synchronize do
          # Resolve the path using the per-method registry keys.
          path = resolve_path_suffix(suffix, per_method_registry.keys)
          return nil unless path

          iseqs = per_method_registry[path]
          return nil unless iseqs

          # Only match event types the instrumenter subscribes to
          # (:line, :return, :b_return — see hook_line). Lines that
          # only carry :call (e.g. a `def` line within the defined
          # method's own iseq, not the enclosing scope) have no
          # subscribed event at that position; TracePoint#enable
          # raises because it cannot bind an enabled event there.
          matching = iseqs.find do |iseq|
            iseq.trace_points.any? do |tp_line, event|
              tp_line == line && (event == :line || event == :return || event == :b_return)
            end
          end
          matching ? [path, matching] : nil
        end
      end

      # Stops tracking code that is being loaded.
      #
      # This method should ordinarily never be called - if a file is loaded
      # when code tracking is not active, this file will not be instrumentable
      # by line probes.
      #
      # This method is intended for test suite use only, where multiple
      # code tracker instances are created, to fully clean up the old instances.
      def stop
        # Permit multiple stop calls.
        trace_point_lock.synchronize do
          @compiled_trace_point&.disable
          # Clear the instance variable so that the trace point may be
          # reinstated in the future.
          @compiled_trace_point = nil
        end
        clear
      end

      # Clears the stored mapping from paths to compiled code.
      #
      # This method should normally never be called. It is meant to be
      # used only by the test suite.
      def clear
        registry_lock.synchronize do
          registry.clear
          per_method_registry.clear
        end
      end

      private

      # Mapping from paths of loaded files to RubyVM::InstructionSequence
      # objects representing compiled code of those files.
      attr_reader :registry

      # Mapping from paths to arrays of per-method/block/class iseqs.
      # Used as fallback when the whole-file iseq has been GC'd.
      attr_reader :per_method_registry

      attr_reader :trace_point_lock
      attr_reader :registry_lock

      # Resolves a path suffix against a set of known paths.
      # Returns the matching path or nil.
      #
      # Must be called within registry_lock.
      def resolve_path_suffix(suffix, paths)
        # Exact match.
        return suffix if paths.include?(suffix)

        # Suffix match.
        suffix = suffix.dup
        loop do
          matches = paths.select { |p| Utils.path_matches_suffix?(p, suffix) }
          return nil if matches.length > 1
          return matches.first if matches.any?
          return nil unless suffix.include?('/')
          suffix.sub!(%r{.*/+}, '')
        end
      end
    end
  end
end

# rubocop:enable Lint/AssignmentInCondition
