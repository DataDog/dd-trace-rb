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
end
