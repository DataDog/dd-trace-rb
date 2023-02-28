module ThreadHelpers
  module_function

  # Isolate created crated in a block in their own `ThreadGroup`.
  # We are then able to identify which threads belong to a specific
  # group, which can help us trace the source of leaky threads.
  def with_leaky_thread_creation(name)
    group = ThreadGroup.new
    group.instance_variable_set(:@group_name, name)

    # Temporarily set current thread to the new group.
    # New threads inherit the group from the executing thread's group.
    group.add(Thread.current)

    # Execute code that creates "leaky" threads
    yield
  ensure
    # Restore current thread to the default group
    ThreadGroup::Default.add(Thread.current)
  end
end
