module LogHelpers
  def without_warnings(&block)
    LogHelpers.without_warnings(&block)
  end

  def self.without_warnings
    v = $VERBOSE
    $VERBOSE = nil
    begin
      yield
    ensure
      $VERBOSE = v
    end
  end

  def without_errors
    level = Datadog::Tracer.log.level
    Datadog::Tracer.log.level = Logger::FATAL
    begin
      yield
    ensure
      Datadog::Tracer.log.level = level
    end
  end
end
