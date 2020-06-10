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
    segments = version.dup.segments
    segments.reverse.each_with_index do |value, i|
      if value.to_i > 0
        segments[segments.length - 1 - i] -= 1
        break
      end
    end
    Gem::Version.new(segments.join('.'))
  end

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

  def self.included(config)
    config.before(:each) do
      allow_any_instance_of(Datadog::Pin)
        .to receive(:deprecation_warning)
        .and_raise('DEPRECATED: Tracer cannot be eagerly cached.' \
      'A warning will be emitted in production for such cases.')
    end
  end
end
