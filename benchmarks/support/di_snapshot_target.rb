class DISnapshotTarget
  def test_method
    # Perform some work to take up time
    SecureRandom.uuid

    v1 = Datadog.configuration
    v2 = Datadog.configuration
    v3 = Datadog.configuration
    v4 = Datadog.configuration
    v5 = Datadog.configuration
    v6 = Datadog.configuration
    v7 = Datadog.configuration
    v8 = Datadog.configuration
    v9 = Datadog.configuration

    # Currently Ruby DI does not implement capture of local variables
    # in method probes, or instance variables.
    # Return a complex object which will be serialized for the
    # enriched probe.
    Datadog.configuration # Line 20
  end
end
