# frozen_string_literal: true

require 'libdatadog'
require 'ffi'

module Datadog
  module Profiling
    module LibdatadogFfi
      extend FFI::Library
      ffi_lib "#{Libdatadog.ld_library_path}/libdatadog_profiling.so"

      # Define CharSlice to be used for string references
      class CharSlice < FFI::Struct
        layout :ptr, :pointer,
               :len, :size_t

        # Helper method to create a CharSlice from a Ruby string
        def self.from_string(str)
          slice = self.new
          slice[:ptr] = FFI::MemoryPointer.from_string(str)
          slice[:len] = str.bytesize
          slice
        end
      end

      class Endpoint < FFI::Struct
        layout :tag, :int,
               :agent, CharSlice
      end

      # Define the custom structures used by the functions
      class CrashtrackerConfiguration < FFI::Struct
        layout :additional_files, :pointer,  # Simplified for this example; actual definition needed
               :create_alt_stack, :bool,
               :endpoint, Endpoint,
               :resolve_frames, :int,
               :timeout_secs, :uint64,
               :wait_for_receiver, :bool
      end

      class CrashtrackerReceiverConfig < FFI::Struct
        layout :args, :pointer,            # Array of strings; actual handling needed
               :env, :pointer,             # FIXME
               :path_to_receiver_binary, CharSlice,
               :optional_stderr_filename, :pointer,
               :optional_stdout_filename, :pointer
      end

      class CrashtrackerMetadata < FFI::Struct
        layout :profiling_library_name, CharSlice,
               :profiling_library_version, CharSlice,
               :family, CharSlice,
               :tags, :pointer             # Tag array; actual handling needed
      end

      # Define ddog_Vec_U8 to represent a Rust Vec holding bytes
      class VecU8 < FFI::Struct
        layout :ptr, :pointer,   # Pointer to the array of bytes
               :len, :uintptr_t, # Number of bytes in the array
               :capacity, :uintptr_t # Capacity of the array
      end

      # Define Error struct which holds a VecU8
      class Error < FFI::Struct
        layout :message, VecU8
      end

      # Define a union to represent the different result types
      class ResultUnion < FFI::Union
        layout :ok, :bool,   # Assuming 'ok' does not need to carry additional data
               :err, Error
      end

      class CrashtrackerResult < FFI::Struct
        layout :tag, :int,                # Enum to indicate success or error
               :result, ResultUnion
      end

      # Function bindings
      attach_function :ddog_prof_Crashtracker_init_with_receiver, [CrashtrackerConfiguration.by_value, CrashtrackerReceiverConfig.by_value, CrashtrackerMetadata.by_value], CrashtrackerResult.by_value
      attach_function :ddog_prof_Crashtracker_update_on_fork, [CrashtrackerConfiguration.by_value, CrashtrackerReceiverConfig.by_value, CrashtrackerMetadata.by_value], CrashtrackerResult.by_value
      attach_function :ddog_prof_Crashtracker_shutdown, [], CrashtrackerResult.by_value

      def self.start
        config = CrashtrackerConfiguration.new
        config[:additional_files] = nil
        config[:create_alt_stack] = false
        config[:endpoint][:tag] = 0
        config[:endpoint][:agent] = CharSlice.from_string('ruby-profiling-agent')
        config[:resolve_frames] = 3
        config[:timeout_secs] = 10
        config[:wait_for_receiver] = true

        receiver_config = CrashtrackerReceiverConfig.new
        receiver_config[:args] = nil
        receiver_config[:env] = nil
        receiver_config[:path_to_receiver_binary] = CharSlice.from_string('/path/to/receiver')
        receiver_config[:optional_stderr_filename] = nil
        receiver_config[:optional_stdout_filename] = nil

        metadata = CrashtrackerMetadata.new
        metadata[:profiling_library_name] = CharSlice.from_string('ruby-profiling')
        metadata[:profiling_library_version] = CharSlice.from_string('0.1.0')
        metadata[:family] = CharSlice.from_string('ruby')
        metadata[:tags] = nil

        result = ddog_prof_Crashtracker_init_with_receiver(config, receiver_config, metadata)

        raise "Failed to start crash tracking: #{result[:result][:err][:message][:ptr].read_string}" unless result[:tag] == 0

        puts 'Crash tracking started successfully'

        result
      end
    end
  end
end

Datadog::Profiling::LibdatadogFfi.start
