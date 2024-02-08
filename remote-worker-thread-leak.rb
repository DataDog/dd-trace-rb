require 'ddtrace'

configure_thread = Thread.new do
  15.times {
    Datadog.configure { Thread.pass }
    Thread.pass
  }
end

trigger_rc_thread = Thread.new do
  loop {
    sleep 0.5
    Datadog::Core::Remote.active_remote.barrier(:once)
    Thread.pass
  }
end

configure_thread.join
trigger_rc_thread.kill
trigger_rc_thread.join

puts Thread.list
