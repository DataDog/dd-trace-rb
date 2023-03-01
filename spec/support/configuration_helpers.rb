require 'bundler'

module ConfigurationHelpers
  shared_context 'loaded gems' do |gems = {}|
    before do
      allow(Gem.loaded_specs).to receive(:[]).and_call_original

      gems.each do |gem_name, version|
        spec = nil

        unless version.nil?
          version = Gem::Version.new(version.to_s)
          spec = instance_double(
            Bundler::StubSpecification,
            version: version
          )
        end

        allow(Gem.loaded_specs).to receive(:[])
          .with(gem_name.to_s)
          .and_return(spec)
      end
    end
  end

  def decrement_gem_version(version)
    segments = version.segments.dup
    segments.reverse.each_with_index do |value, i|
      if value.to_i > 0
        segments[segments.length - 1 - i] -= 1
        break
      end
    end
    Gem::Version.new(segments.join('.'))
  end

  def remove_patch!(integration, patch_key = :patch)
    if (integration.is_a?(Module) || integration.is_a?(Class)) && integration <= Datadog::Tracing::Contrib::Patcher
      integration::PATCH_ONLY_ONCE.send(:reset_ran_once_state_for_tests) if defined?(integration::PATCH_ONLY_ONCE)
      if integration.respond_to?(:patch_only_once, true)
        integration.send(:patch_only_once).send(:reset_ran_once_state_for_tests)
      end
    elsif Datadog.registry[integration].respond_to?(:patcher)
      Datadog.registry[integration].patcher.tap do |patcher|
        patcher::PATCH_ONLY_ONCE.send(:reset_ran_once_state_for_tests) if defined?(patcher::PATCH_ONLY_ONCE)
        patcher.send(:patch_only_once).send(:reset_ran_once_state_for_tests) if patcher.respond_to?(:patch_only_once, true)
      end
    else
      Datadog
        .registry[integration]
        .instance_variable_set('@patched', false)
    end
  end
end
