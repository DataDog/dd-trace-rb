module ConfigurationHelpers
  def remove_patch!(integration, patch_key = :patch)
    if (integration.is_a?(Module) || integration.is_a?(Class)) && integration <= Datadog::Contrib::Patcher
      if integration.instance_variable_defined?(:@done_once)
        integration.instance_variable_get(:@done_once).delete(patch_key)
      end
    elsif Datadog.registry[integration].respond_to?(:patcher)
      Datadog.registry[integration].patcher.tap do |patcher|
        if patcher.instance_variable_defined?(:@done_once)
          patcher.instance_variable_get(:@done_once).delete(patch_key)
        end
      end
    else
      Datadog
        .registry[integration]
        .instance_variable_set('@patched', false)
    end
  end
end
