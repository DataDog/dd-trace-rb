module ConfigurationHelpers
  def remove_patch!(integration)
    if Datadog.registry[integration].respond_to?(:patcher)
      Datadog.registry[integration].patcher.tap do |patcher|
        if patcher.instance_variable_defined?(:@done_once)
          patcher.instance_variable_get(:@done_once).delete(integration)
        end
      end
    else
      Datadog
        .registry[integration]
        .instance_variable_set('@patched', false)
    end
  end
end
