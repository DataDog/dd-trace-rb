# frozen_string_literal: true

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
        @trace_point_lock = Mutex.new
        @registry_lock = {}
      end

      def start
        # If this code tracker is already running, we can do nothing or
        # restart it (by disabling the trace point and recreating it).
        # It is likely that some applications will attempt to activate
        # DI more than once where the intention is to just activate DI;
        # do not break such applications by clearing out the registry.
        # For now, until there is a use case for recreating the trace point,
        # do nothing if the code tracker has already started.
        return if active?

        compiled_trace_point = TracePoint.trace(:script_compiled) do |tp|
          # Useful attributes of the trace point object here:
          # .instruction_sequence
          # .method_id
          # .path (refers to the code location that called the require/eval/etc.,
          #   not where the loaded code is; use .path on the instruction sequence
          #   to obtain the location of the compiled code)
          # .eval_script
          #
          # For now just map the path to the instruction sequence.
          path = tp.instruction_sequence.path
          registry_lock.synchronize do
            registry[path] = tp.instruction_sequence
          end
        end

        trace_point_lock.synchronize do
          # Since trace point creation itself is not under a lock, see if
          # another thread created the trace point, in which case we can
          # disable our trace point and do nothing.
          if @compiled_trace_point
            # Disable the local variable, leave instance variable as it is.
            compiled_trace_point.disable
            return
          end

          @compiled_trace_point = compiled_trace_point
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
      def iseqs_for_path(suffix)
        registry_lock.synchronize do
          exact = registry[suffix]
          return [exact] if exact

          inexact = []
          registry.each do |path, iseq|
            # Exact match is not possible here, meaning any matching path
            # has to be longer than the suffix. Require full component matches,
            # meaning either the first character of the suffix is a slash
            # or the previous character in the path is a slash.
            # For now only check for forward slashes for Unix-like OSes;
            # backslash is a legitimate character of a file name in Unix
            # therefore simply permitting forward or back slash is not
            # sufficient, we need to perform an OS check to know which
            # path separator to use.
            if path.length > suffix.length && (
              path[path.length - suffix.length - 1] == "/" ||
              suffix[0] == "/"
            ) && path.end_with?(suffix)
              inexact << iseq
            end
          end
          inexact
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
        registry_lock.synchronize do
          registry.clear
        end
      end

      private

      # Mapping from paths of loaded files to RubyVM::InstructionSequence
      # objects representing compiled code of those files.
      attr_reader :registry

      attr_reader :trace_point_lock
      attr_reader :registry_lock
    end
  end
end
