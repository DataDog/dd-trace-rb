require 'pry'
require 'libdatadog'
require 'libdatadog_ruby'

# TODO: Move this inside swig...
def to_charslice(string)
  Libdatadog_ruby::Ddog_Slice_CChar.new.tap do |it|
    it.ptr = string
    it.len = string.bytesize
  end
end

def trigger
  config = Libdatadog_ruby::Ddog_prof_CrashtrackerConfiguration.new
  # config.additional_files = # Leave it empty
  config.create_alt_stack = false
  # Todo: Can we group "classes" inside swig?
  config.endpoint = Libdatadog_ruby.ddog_prof_Endpoint_agent(to_charslice('http://localhost:8126/'))
  config.resolve_frames = Libdatadog_ruby::DDOG_PROF_STACKTRACE_COLLECTION_ENABLED_WITH_SYMBOLS_IN_RECEIVER
  config.timeout_secs = 10
  config.wait_for_receiver = true

  metadata = Libdatadog_ruby::Ddog_prof_CrashtrackerMetadata.new
  metadata.profiling_library_name = to_charslice("dd-trace-rb123")
  metadata.profiling_library_version = to_charslice("this-is-a-version")
  metadata.family = to_charslice("this-is-a-family")
  #metadata.tags # no tags for now

  receiver_config = Libdatadog_ruby::Ddog_prof_CrashtrackerReceiverConfig.new
  # receiver_config.args  # no args for now
  #receiver_config.env  # no env for now
  receiver_config.path_to_receiver_binary = to_charslice(Libdatadog.path_to_crashtracking_receiver_binary)
  #receiver

  result = Libdatadog_ruby::ddog_prof_Crashtracker_init_with_receiver(config, receiver_config, metadata)

  if result.tag == Libdatadog_ruby::DDOG_PROF_CRASHTRACKER_RESULT_ERR
    puts "Failed to start: #{result.err}"
  else
    puts "Started successfully!"
  end
end

trigger

puts "Libdatadog reports library path as #{Libdatadog.ld_library_path}"
ENV['LD_LIBRARY_PATH'] = Libdatadog.ld_library_path

puts "Crashing Ruby..."
Process.kill('SEGV', Process.pid)
