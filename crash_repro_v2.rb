Datadog::Profiling.wait_until_running

class DummyObject; end
$the_proc = proc do |*args, **kwargs|
  args.size > 0 ? kwargs.size : nil

  # puts "called finalizer!"
end

def create_dummy_object
  o = DummyObject.new
  ObjectSpace.define_finalizer(o, $the_proc)
end

def trigger
  loop do
    create_dummy_object
    10.times { Object.new }
    GC.start(immediate_mark: false, immediate_sweep: false, full_mark: false)
  end
end

trigger
