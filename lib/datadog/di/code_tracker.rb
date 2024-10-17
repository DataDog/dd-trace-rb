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
        @registry_lock = Mutex.new
        @compiled_trace_point = nil
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
            end
          end
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
          return [exact] if exact

          inexact = []
          registry.each do |path, iseq|
            if Utils.path_matches_suffix?(path, suffix)
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
        clear
      end

      # Clears the stored mapping from paths to compiled code.
      #
      # This method should normally never be called. It is meant to be
      # used only by the test suite.
      def clear
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
