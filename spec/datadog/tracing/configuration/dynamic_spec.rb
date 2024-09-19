# frozen_string_literal: true

require 'rspec'

RSpec.shared_examples 'tracing dynamic simple option' do |name:, env_var:, config_key:, value:, config_object: nil|
  let(:option) { described_class.new }
  let(:configuration_object) { config_object || Datadog.configuration.tracing }
  let(:new_value) { value }
  let(:old_value) { configuration_object.public_send(config_key) }

  before do
    configuration_object.reset!
    old_value
  end

  describe '#call' do
    subject(:call) { option.call(new_value) }

    it "changes #{config_key} to #{value}" do
      expect { call }.to change { configuration_object.public_send(config_key) }.from(old_value).to(value)
    end

    it "declares environment variable name as #{env_var}" do
      expect(option.env_var).to eq(env_var)
    end

    it "declares option name as #{name}" do
      expect(option.name).to eq(name)
    end

    context 'with nil value' do
      before { call }

      it "restores original value before dynamic configuration #{config_key}" do
        expect { option.call(nil) }.to change { configuration_object.public_send(config_key) }.from(value).to(old_value)
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Configuration::Dynamic::LogInjectionEnabled do
  include_examples 'tracing dynamic simple option',
    name: 'log_injection_enabled',
    env_var: 'DD_LOGS_INJECTION',
    config_key: :log_injection,
    value: false
end

RSpec.describe Datadog::Tracing::Configuration::Dynamic::TracingHeaderTags do
  include_examples 'tracing dynamic simple option',
    name: 'tracing_header_tags',
    env_var: 'DD_TRACE_HEADER_TAGS',
    config_key: :header_tags,
    value: RSpec::Matchers::BuiltIn::Match.new(->(header_tags) { header_tags.to_s == 'my-header:my-tag' }) do
      let(:old_value) { ->(header_tags) { header_tags.to_s == '' } }
      let(:new_value) { [{ 'header' => 'my-header', 'tag_name' => 'my-tag' }] }
    end

  context 'with multiple values in tracing_header_tags' do
    let(:new_value) { [{ 'header' => 'h1', 'tag_name' => 't1' }, { 'header' => 'h2', 'tag_name' => '' }] }

    it 'process the value list' do
      expect(configuration_object).to receive(:set_option).with(:header_tags, ['h1:t1', 'h2:'], any_args)
      option.call(new_value)
    end
  end
end

RSpec.describe Datadog::Tracing::Configuration::Dynamic::TracingSamplingRate do
  include_examples 'tracing dynamic simple option',
    name: 'tracing_sampling_rate',
    env_var: 'DD_TRACE_SAMPLE_RATE',
    config_key: :default_rate,
    value: 0.2,
    config_object: Datadog.configuration.tracing.sampling

  it 'reconfigures the live sampler' do
    expect(Datadog.send(:components)).to receive(:reconfigure_live_sampler)
    option.call(new_value)
  end
end

RSpec.describe Datadog::Tracing::Configuration::Dynamic::TracingSamplingRules do
  let(:old_value) { nil }

  include_examples 'tracing dynamic simple option',
    name: 'tracing_sampling_rules',
    env_var: 'DD_TRACE_SAMPLING_RULES',
    config_key: :rules,
    value: RSpec::Matchers::BuiltIn::Match.new(->(rules) { rules == '[{"sample_rate":1}]' }),
    config_object: Datadog.configuration.tracing.sampling do
      let(:new_value) { [{ sample_rate: 1 }] }
    end

  context 'with tags' do
    include_examples 'tracing dynamic simple option',
      name: 'tracing_sampling_rules',
      env_var: 'DD_TRACE_SAMPLING_RULES',
      config_key: :rules,
      value: RSpec::Matchers::BuiltIn::Match.new(
        lambda do |rules|
          rules == '[{"sample_rate":1,"tags":[{"key":"k","value_glob":"v"}]}]'
        end
      ),
      config_object: Datadog.configuration.tracing.sampling do
        let(:new_value) { [{ sample_rate: 1, tags: [{ key: 'k', value_glob: 'v' }] }] }
      end
  end

  it 'reconfigures the live sampler' do
    expect(Datadog.send(:components)).to receive(:reconfigure_live_sampler)
    option.call(new_value)
  end
end
