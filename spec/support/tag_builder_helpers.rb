module TagBuilderHelpers
  # Resets caches in this module.
  def reset_for_tests
    remove_instance_variable(:@fixed_environment_tags) if defined?(@fixed_environment_tags)
  end
end

Datadog::Core::TagBuilder.extend TagBuilderHelpers
