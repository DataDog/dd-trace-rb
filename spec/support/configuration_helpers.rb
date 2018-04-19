module ConfigurationHelpers
  def remove_patch!(integration)
    Datadog
      .registry[integration]
      .instance_variable_set('@patched', false)
  end
end
