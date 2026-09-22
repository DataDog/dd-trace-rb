# Loaded into a Ruby::Box by stack_spec.rb: monkey patching a core class inside a box makes Ruby keep a box-local
# copy of the class internals. The box can't see `Datadog`, so the sampler is passed in.

class String
  def method_patched_in_box
    yield
  end
end

class BoxedSampler
  def self.sample(sampler, recorder, metric_values, labels)
    "a string".method_patched_in_box do
      sampler._native_sample(
        Thread.current,
        recorder,
        metric_values,
        labels,
        [],
        native_filenames_enabled: false,
        show_classes: true,
      )
    end
  end
end
