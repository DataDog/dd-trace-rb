# This class must live in a separate file so that it can be loaded
# after code tracking for dynamic instrumentation is enabled.
class DITarget
  # This method must have an executable line as its first line,
  # otherwise line instrumentation won't work.
  # The code in this method should be identical to
  # DIInstrumentMethodBenchmark#test_method.
  # The two methods are separate so that instrumentation targets are
  # different, to avoid a false positive if line instrumemntation fails
  # to work and method instrumentation isn't cleared and continues to
  # invoke the callback.
  def test_method_for_line_probe
    SecureRandom.uuid
  end
end
