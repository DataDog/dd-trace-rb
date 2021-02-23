require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'

  gem 'ffi'
  gem 'pry'
end

require 'ffi'
require 'pry'

module MacStuff
  extend FFI::Library
  ffi_lib FFI::CURRENT_PROCESS

  MACOS_INTEGER_T = :int      # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/i386/vm_types.h#L93
  MACOS_POLICY_T = :int       # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/policy.h#L79

  class StructTimeValue < FFI::Struct
    layout(
      seconds: MACOS_INTEGER_T,
      microseconds: MACOS_INTEGER_T,
    )

    def to_h
      members.map { |member| [member, self[member]] }.to_h
    end

    def inspect
      to_h.to_s
    end
  end

  class MachMsgTypeNumberT < FFI::Struct
    layout(
      fixme: :uint,
    )

    def to_h
      members.map { |member| [member, self[member]] }.to_h
    end

    def inspect
      to_h.to_s
    end
  end

  MACOS_TIME_VALUE_T = StructTimeValue

  class StructThreadBasicInfo < FFI::Struct
    # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/thread_info.h#L92
    layout(
      user_time:     MACOS_TIME_VALUE_T,
      system_time:   MACOS_TIME_VALUE_T,
      cpu_usage:     MACOS_INTEGER_T,
      policy:        MACOS_POLICY_T,
      run_state:     MACOS_INTEGER_T,
      flags:         MACOS_INTEGER_T,
      suspend_count: MACOS_INTEGER_T,
      sleep_time:    MACOS_INTEGER_T,
    )

    def to_h
      members.map { |member| [member, self[member]] }.to_h
    end

    def inspect
      to_h.to_s
    end
  end

  attach_function(
    :mach_thread_self, # http://web.mit.edu/darwin/src/modules/xnu/osfmk/man/mach_thread_self.html
                       # https://github.com/apple/darwin-xnu/blob/8f02f2a044b9bb1ad951987ef5bab20ec9486310/libsyscall/mach/mach/mach_init.h#L73
    [],                # no args
    :uint,             # mach_port_t => __darwin_mach_port_t => __darwin_mach_port_name_t => __darwin_natural_t => unsigned int
  )
  attach_function(
    :thread_basic_info,
    :thread_info,      # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/thread_act.defs#L241
                       # https://developer.apple.com/documentation/kernel/1418630-thread_info
    [
      :uint,           # thread_inspect_it => mach_port_t => (see above)
      :uint,           # thread_flavor_t => natural_t => __darwin_natural_t => (see above)
      StructThreadBasicInfo.by_ref,
      MachMsgTypeNumberT.by_ref,         # mach_msg_type_number_t *thread_info_outCnt
    ],
    :int,              # kern_return_t
  )

  THREAD_BASIC_INFO = 3 # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/thread_info.h#L90

  THREAD_BASIC_INFO_COUNT = MacStuff::StructThreadBasicInfo.size / FFI::TypeDefs[:uint].size

  class StructThreadExtendedInfo < FFI::Struct
    layout(
      pth_user_time: :uint64,
      pth_system_time: :uint64,
      pth_cpu_usage: :int32,
      pth_policy: :int32,
      pth_run_state: :int32,
      pth_flags: :int32,
      pth_sleep_time: :int32,
      pth_curpri: :int32,
      pth_priority: :int32,
      pth_maxpriority: :int32,
      pth_name: [:char, 64],
    )

    def to_h
      members.map { |member| [member, self[member]] }.to_h
    end

    def inspect
      to_h.to_s
    end
  end

  THREAD_EXTENDED_INFO = 5
  THREAD_EXTENDED_INFO_COUNT = MacStuff::StructThreadExtendedInfo.size / FFI::TypeDefs[:uint].size

  attach_function(
    :thread_extended_info,
    :thread_info,      # https://github.com/apple/darwin-xnu/blob/main/osfmk/mach/thread_act.defs#L241
                       # https://developer.apple.com/documentation/kernel/1418630-thread_info
    [
      :uint,           # thread_inspect_it => mach_port_t => (see above)
      :uint,           # thread_flavor_t => natural_t => __darwin_natural_t => (see above)
      StructThreadExtendedInfo.by_ref,
      MachMsgTypeNumberT.by_ref,         # mach_msg_type_number_t *thread_info_outCnt
    ],
    :int,              # kern_return_t
  )
end

# We can also get the port from the pthread id using pthread_mach_thread_np(pthread), see https://opensource.apple.com/source/Libc/Libc-498/pthreads/pthread.c
current_thread_port = MacStuff.mach_thread_self

thread_basic_info = MacStuff::StructThreadBasicInfo.new

thread_info_out_cnt = MacStuff::MachMsgTypeNumberT.new
thread_info_out_cnt[:fixme] = MacStuff::THREAD_BASIC_INFO_COUNT

start_time = Time.now
finish_time = start_time + 5

rand while (Time.now < finish_time)

thread_info_result = MacStuff.thread_basic_info(current_thread_port, MacStuff::THREAD_BASIC_INFO, thread_basic_info, thread_info_out_cnt)

if thread_info_result == 0
  puts "Success!"
else
  puts "Call failed with error #{thread_info_result}" # see kern_return.h
end

thread_extended_info = MacStuff::StructThreadExtendedInfo.new
thread_extended_info_out_cnt = MacStuff::MachMsgTypeNumberT.new
thread_extended_info_out_cnt[:fixme] = MacStuff::THREAD_EXTENDED_INFO_COUNT

thread_extended_info_result = MacStuff.thread_extended_info(current_thread_port, MacStuff::THREAD_EXTENDED_INFO, thread_extended_info, thread_extended_info_out_cnt)

if thread_extended_info_result == 0
  puts "Success!"
else
  puts "Call failed with error #{thread_extended_info_result}" # see kern_return.h
end

puts "This thread took #{(thread_extended_info[:pth_user_time] + thread_extended_info[:pth_system_time]).to_f / 1_000_000_000}s to run"

binding.pry
