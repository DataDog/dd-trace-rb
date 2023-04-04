require 'spec_helper'

require 'ddtrace/transport/http/builder'

RSpec.describe Datadog::Transport::HTTP::Builder do
  subject(:builder) { described_class.new }

  describe '#initialize' do
    context 'given a block' do
      it { expect { |b| described_class.new(&b) }.to yield_with_args(kind_of(described_class)) }
    end
  end

  describe '#adapter' do
    context 'given AgentSettings' do
      subject(:adapter) { builder.adapter(config) }

      let(:config) do
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: config_adapter,
          ssl: nil,
          hostname: nil,
          port: nil,
          uds_path: nil,
          timeout_seconds: nil,
          deprecated_for_removal_transport_configuration_proc: nil,
        )
      end
      let(:config_adapter) { :adapter_foo }

      context 'that matches an adapter in the registry' do
        let(:adapter_class) { double('adapter class') }
        let(:adapter_object) { double('adapter object') }

        before do
          allow(described_class::REGISTRY).to receive(:get).with(config_adapter).and_return(adapter_class)

          expect(adapter_class).to receive(:build).with(config).and_return(adapter_object)
        end

        it 'changes the default adapter' do
          is_expected.to be adapter_object
          expect(builder.default_adapter).to be adapter_object
        end
      end

      context 'that does not match an adapter in the registry' do
        it { expect { adapter }.to raise_error(described_class::UnknownAdapterError) }
      end
    end

    context 'given a symbol' do
      subject(:adapter) { builder.adapter(type, *args, **kwargs) }

      let(:type) { :foo }
      let(:args) { [double('arg1'), double('arg2')] }
      let(:kwargs) { { kwarg: double('kwval') } }

      context 'that matches an adapter in the registry' do
        let(:adapter_class) { double('adapter class') }
        let(:adapter_object) { double('adapter object') }

        before do
          allow(described_class::REGISTRY).to receive(:get)
            .with(type)
            .and_return(adapter_class)

          expect(adapter_class).to receive(:new)
            .with(*args, **kwargs)
            .and_return(adapter_object)
        end

        it 'changes the default adapter' do
          is_expected.to be adapter_object
          expect(builder.default_adapter).to be adapter_object
        end
      end

      context 'that does not match an adapter in the registry' do
        it { expect { adapter }.to raise_error(described_class::UnknownAdapterError) }
      end
    end

    context 'given an adapter object' do
      subject(:adapter) { builder.adapter(adapter_object) }

      let(:adapter_object) { double('adapter object') }

      it 'changes the default adapter' do
        is_expected.to be adapter_object
        expect(builder.default_adapter).to be adapter_object
      end
    end
  end

  describe '#headers' do
    let(:first_headers) { { 'X-Test-One' => 'foo', 'X-Test-Two' => 'bar' } }
    let(:second_headers) { { 'X-Test-Two' => 'blah', 'X-Test-Three' => 'baz' } }

    let(:expected_headers) do
      {
        'X-Test-One' => 'foo',
        'X-Test-Two' => 'blah',
        'X-Test-Three' => 'baz'
      }
    end

    it 'merges headers when invoked multiple times' do
      expect(builder.headers(first_headers)).to eq(first_headers)
      expect(builder.headers(second_headers)).to eq(expected_headers)
      expect(builder.default_headers).to eq(expected_headers)
    end
  end

  describe '#api' do
    subject(:api) { builder.api(key, spec, options) }

    let(:key) { :v2 }
    let(:spec) { instance_double(Datadog::Transport::HTTP::API::Spec) }
    let(:options) { {} }

    context 'when no APIs have been configured' do
      it 'adds the API and sets it as the default' do
        expect { api }.to change { builder.default_api }.from(nil).to(key)
        expect(builder.apis).to include(key => spec)
      end
    end

    context 'when an API has already been configured' do
      before { builder.api(:v1, instance_double(Datadog::Transport::HTTP::API::Spec)) }

      it 'adds the API but does not set it as the default' do
        expect { api }.to_not(change { builder.default_api })
        expect(builder.apis).to include(key => spec)
      end

      context 'and is given \'default: true\'' do
        let(:options) { { default: true } }

        it 'adds the API and sets it as the default' do
          expect { api }.to change { builder.default_api }.from(:v1).to(key)
          expect(builder.apis).to include(key => spec)
        end
      end
    end

    context 'when configured with additional options' do
      let(:options) { { foo: :foo } }

      it do
        api
        expect(builder.apis).to include(key => spec)
        expect(builder.api_options).to include(key => options)
      end

      context 'multiple times' do
        let(:first_options) { { foo: :foo, bar: :bar } }
        let(:second_options) { { bar: :blah, baz: :baz } }

        let(:expected_options) { { foo: :foo, bar: :blah, baz: :baz } }

        it 'merges options' do
          builder.api(key, spec, first_options)
          expect(builder.apis).to include(key => spec)
          expect(builder.api_options).to include(key => first_options)
          # Second pass
          builder.api(key, spec, second_options)
          expect(builder.apis).to include(key => spec)
          expect(builder.api_options).to include(key => expected_options)
        end
      end
    end
  end

  describe '#default_api=' do
    subject(:default_api) { builder.default_api = key }

    let(:key) { double('API key') }

    before { builder.api :original, instance_double(Datadog::Transport::HTTP::API::Spec), default: true }

    context 'which matches an already defined API' do
      before { builder.api key, instance_double(Datadog::Transport::HTTP::API::Spec) }

      it { expect { default_api }.to change { builder.default_api }.from(:original).to(key) }
    end

    context 'which does not match any defined API' do
      it { expect { default_api }.to raise_error(described_class::UnknownApiError) }
    end
  end

  describe '#to_api_instances' do
    subject(:api_instances) { builder.to_api_instances }

    shared_context 'default adapter' do
      before { builder.adapter(adapter) }

      let(:adapter) { double('adapter') }
    end

    context 'when no APIs are defined' do
      it { expect { api_instances }.to raise_error(described_class::NoApisError) }
    end

    context 'when an API is defined' do
      before { builder.api(key, spec, options) }

      let(:key) { :v2 }
      let(:spec) { instance_double(Datadog::Transport::HTTP::API::Spec) }
      let(:options) { {} }

      context 'but no adapter is defined anywhere' do
        it { expect { api_instances }.to raise_error(described_class::NoAdapterForApiError) }
      end

      context 'which inherits from the default adapter' do
        include_context 'default adapter'

        it 'configures the API instance with the default adapter' do
          expect(api_instances).to include(key => kind_of(builder.api_instance_class))
          expect(api_instances[key].adapter).to be adapter
        end
      end

      context 'which specifies its own adapter' do
        let(:options) { { adapter: adapter } }
        let(:adapter) { double('adapter') }

        it 'configures the API instance with the given adapter' do
          expect(api_instances).to include(key => kind_of(builder.api_instance_class))
          expect(api_instances[key].adapter).to be adapter
        end
      end

      context 'which specifies custom options' do
        # Assume an adapter is available.
        include_context 'default adapter'

        let(:options) { { foo: :bar } }

        before do
          expect(builder.api_instance_class).to receive(:new)
            .with(spec, adapter, { foo: :bar, headers: {} })
            .and_call_original
        end

        it 'configures the API instance with custom options' do
          expect(api_instances).to include(key => kind_of(builder.api_instance_class))
        end
      end

      context 'which specifies a fallback' do
        # Assume an adapter is available.
        include_context 'default adapter'

        let(:options) { { fallback: fallback_key } }
        let(:fallback_key) { :v1 }
        let(:fallback_spec) { instance_double(Datadog::Transport::HTTP::API::Spec) }

        before { builder.api(fallback_key, fallback_spec) }

        it 'configures the map with a fallback' do
          expect(api_instances).to include(
            key => kind_of(builder.api_instance_class),
            fallback_key => kind_of(builder.api_instance_class)
          )
          expect(api_instances.fallbacks[key]).to eq(fallback_key)
        end
      end

      context 'which specifies headers' do
        # Assume an adapter is available.
        include_context 'default adapter'

        let(:options) { { headers: api_headers } }
        let(:api_headers) { { 'X-Test-One' => 'foo' } }

        context 'and there are no default headers defined' do
          it 'configures the API instance with the given adapter' do
            expect(api_instances).to include(key => kind_of(builder.api_instance_class))
            expect(api_instances[key].headers).to eq(api_headers)
          end
        end

        context 'which conflict with default headers' do
          let(:api_headers) { { 'X-Test-Two' => 'blah', 'X-Test-Three' => 'baz' } }

          before { builder.headers('X-Test-One' => 'foo', 'X-Test-Two' => 'bar') }

          it 'configures the API instance with the given adapter' do
            expect(api_instances).to include(key => kind_of(builder.api_instance_class))
            expect(api_instances[key].headers).to eq(
              'X-Test-One' => 'foo',
              'X-Test-Two' => 'blah',
              'X-Test-Three' => 'baz'
            )
          end
        end
      end
    end
  end

  describe '#to_transport' do
    subject(:transport) { builder.to_transport }

    context 'when no default API has been defined' do
      it { expect { transport }.to raise_error(described_class::NoDefaultApiError) }
    end

    context 'when APIs and an adapter are defined' do
      let(:spec) { instance_double(Datadog::Transport::HTTP::API::Spec) }

      before do
        builder.adapter(double('adapter'))
        builder.api(:v2, spec)
      end

      it 'returns an HTTP::Transport' do
        expect(transport).to be_a_kind_of(Datadog::Transport::Traces::Transport)
        expect(transport.current_api.spec).to eq(spec)
        expect(transport.apis).to include(v2: kind_of(Datadog::Transport::HTTP::API::Instance))
      end
    end
  end

  describe '#api_instance_class' do
    subject(:api_instance_class) { builder.api_instance_class }

    it { is_expected.to be(Datadog::Transport::HTTP::API::Instance) }
  end
end
