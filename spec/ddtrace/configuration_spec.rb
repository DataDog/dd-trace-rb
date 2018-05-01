require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration do
  let(:configuration) { described_class.new(registry: registry) }
  let(:registry) { Datadog::Registry.new }

  describe '#use' do
    subject(:result) { configuration.use(name, options) }
    let(:name) { :example }
    let(:integration) { double('integration') }
    let(:options) { {} }

    before(:each) do
      registry.add(name, integration)
    end

    context 'for a generic integration' do
      before(:each) do
        expect(integration).to receive(:sorted_options).and_return([])
        expect(integration).to receive(:patch).and_return(true)
      end

      it { expect { result }.to_not raise_error }
    end

    context 'for an integration that includes Datadog::Contrib::Base' do
      let(:options) { { option1: :foo!, option2: :bar! } }
      let(:integration) do
        Module.new do
          include Datadog::Contrib::Base
          option :option1
          option :option2
        end
      end

      it do
        expect { result }.to_not raise_error
        expect(configuration[name][:option1]).to eq(:foo!)
        expect(configuration[name][:option2]).to eq(:bar!)
      end

      context 'and has a lazy option' do
        let(:integration) do
          Module.new do
            include Datadog::Contrib::Base
            option :option1, default: -> { 1 + 1 }, lazy: true
          end
        end

        it { expect(configuration[name][:option1]).to eq(2) }
      end

      context 'and has dependencies' do
        let(:options) { { multiply_by: 5, number: 5 } }
        let(:integration) do
          Module.new do
            include Datadog::Contrib::Base
            option :multiply_by, depends_on: [:number] do |value|
              get_option(:number) * value
            end

            option :number
          end
        end

        it do
          expect { result }.to_not raise_error
          expect(configuration[name][:number]).to eq(5)
          expect(configuration[name][:multiply_by]).to eq(25)
        end
      end

      context 'and has a setter' do
        let(:array) { [] }
        let(:options) { { option1: :foo! } }
        let(:integration) do
          arr = array
          Module.new do
            include Datadog::Contrib::Base
            option :option1
            option :option2, default: 10 do |value|
              arr << value
              value
            end
          end
        end

        it 'pass through the setter' do
          expect { result }.to_not raise_error
          expect(configuration[name][:option1]).to eq(:foo!)
          expect(configuration[name][:option2]).to eq(10)
          expect(array).to include(10)
        end
      end

      context 'when a setting is changed' do
        before(:each) { configuration[name][:option1] = :foo }
        it { expect(configuration[:example][:option1]).to eq(:foo) }
      end

      context 'when coerced to a hash' do
        let(:integration) do
          Module.new do
            include Datadog::Contrib::Base
            option :option1, default: :foo
            option :option2, default: :bar
          end
        end

        it { expect(configuration[name].to_h).to eq(option1: :foo, option2: :bar) }
      end
    end

    context 'for an integration that includes Datadog::Contrib::Integration' do
      let(:integration_class) do
        Class.new do
          include Datadog::Contrib::Integration
        end
      end

      let(:integration) do
        integration_class.new(name)
      end

      context 'which is provided only a name' do
        it do
          expect(integration).to receive(:configure).with(:default, {})
          configuration.use(name)
        end
      end

      context 'which is provided a block' do
        it do
          expect(integration).to receive(:configure).with(:default, {}).and_call_original
          expect { |b| configuration.use(name, options, &b) }.to yield_with_args(
            a_kind_of(Datadog::Contrib::Configuration::Settings)
          )
        end
      end
    end
  end

  describe '#tracer' do
    let(:tracer) { Datadog::Tracer.new }
    let(:debug_state) { tracer.class.debug_logging }
    let(:custom_log) { Logger.new(STDOUT) }

    context 'given some settings' do
      before(:each) do
        @original_log = tracer.class.log

        configuration.tracer(
          enabled: false,
          debug: !debug_state,
          log: custom_log,
          hostname: 'tracer.host.com',
          port: 1234,
          env: :config_test,
          tags: { foo: :bar },
          instance: tracer
        )
      end

      after(:each) do
        tracer.class.debug_logging = debug_state
        tracer.class.log = @original_log
      end

      it 'applies settings correctly' do
        expect(tracer.enabled).to be false
        expect(debug_state).to be false
        expect(Datadog::Tracer.log).to eq(custom_log)
        expect(tracer.writer.transport.hostname).to eq('tracer.host.com')
        expect(tracer.writer.transport.port).to eq(1234)
        expect(tracer.tags[:env]).to eq(:config_test)
        expect(tracer.tags[:foo]).to eq(:bar)
      end
    end

    it 'acts on the default tracer' do
      previous_state = Datadog.tracer.enabled
      configuration.tracer(enabled: !previous_state)
      expect(Datadog.tracer.enabled).to_not eq(previous_state)
      configuration.tracer(enabled: previous_state)
      expect(Datadog.tracer.enabled).to eq(previous_state)
    end
  end

  describe '#[]' do
    context 'when the integration doesn\'t exist' do
      it do
        expect { configuration[:foobar] }.to raise_error(Datadog::Configuration::InvalidIntegrationError)
      end
    end
  end
end
