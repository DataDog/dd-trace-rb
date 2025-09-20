require 'datadog/tracing/contrib/graphql/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Configuration::Settings do
  describe 'schemas' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.schemas).to eq([])
      end
    end

    context 'when given an array' do
      it do
        schema = double

        settings = described_class.new(schemas: [schema])

        expect(settings.schemas).to eq([schema])
      end
    end

    context 'when given an empty array' do
      it do
        settings = described_class.new(schemas: [])

        expect(settings.schemas).to eq([])
      end
    end
  end

  describe 'with_deprecated_tracer' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.with_deprecated_tracer).to eq(false)
      end
    end

    context 'when given `true`' do
      it do
        settings = described_class.new(with_deprecated_tracer: true)

        expect(settings.with_deprecated_tracer).to eq(true)
      end
    end

    context 'when given `false`' do
      it do
        settings = described_class.new(with_deprecated_tracer: false)

        expect(settings.with_deprecated_tracer).to eq(false)
      end
    end
  end

  describe 'with_unified_tracer' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.with_unified_tracer).to eq(false)
      end
    end

    context 'when given `true`' do
      it do
        settings = described_class.new(with_unified_tracer: true)

        expect(settings.with_unified_tracer).to eq(true)
      end
    end

    context 'when given `false`' do
      it do
        settings = described_class.new(with_unified_tracer: false)

        expect(settings.with_unified_tracer).to eq(false)
      end
    end
  end

  describe 'error_extensions' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.error_extensions).to eq([])
      end
    end

    context 'when given an array' do
      it do
        error_extension = double

        settings = described_class.new(error_extensions: [error_extension])

        expect(settings.error_extensions).to eq([error_extension])
      end

      context 'via the environment variable' do
        it do
          error_extension = 'foo,bar'

          ClimateControl.modify('DD_TRACE_GRAPHQL_ERROR_EXTENSIONS' => error_extension) do
            settings = described_class.new

            expect(settings.error_extensions).to eq(['foo', 'bar'])
          end
        end
      end
    end
  end

  describe 'error_tracking' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.error_tracking).to eq(false)
      end
    end

    context 'when given `true`' do
      it do
        settings = described_class.new(error_tracking: true)

        expect(settings.error_tracking).to eq(true)
      end
    end

    context 'when given `false`' do
      it do
        settings = described_class.new(error_tracking: false)

        expect(settings.error_tracking).to eq(false)
      end
    end
  end

  shared_examples 'capture variables configuration' do |option_name, env_var|
    subject(:config) { settings.public_send(option_name) }
    let(:settings) { described_class.new }

    context 'when default' do
      it { is_expected.to be_a(Datadog::Tracing::Contrib::GraphQL::Configuration::CaptureVariables) }
      it { is_expected.to be_empty }
    end

    context 'when given an array' do
      let(:settings) { described_class.new(option_name => ['GetUser:id', 'GetPost:title']) }

      it 'configures the capture variables correctly' do
        expect(config.matcher_for('GetUser')).to contain_exactly('id')
        expect(config.matcher_for('GetPost')).to contain_exactly('title')
      end
    end

    context 'via the environment variable' do
      it 'configures from environment variable' do
        ClimateControl.modify(env_var => 'GetUser:id,GetPost:title') do
          expect(config.matcher_for('GetUser')).to contain_exactly('id')
          expect(config.matcher_for('GetPost')).to contain_exactly('title')
        end
      end

      context 'with empty string' do
        it 'handles empty environment variable' do
          ClimateControl.modify(env_var => '') do
            expect(config.empty?).to be true
          end
        end
      end
    end
  end

  describe 'capture_variables' do
    include_examples 'capture variables configuration',
      :capture_variables,
      'DD_TRACE_GRAPHQL_CAPTURE_VARIABLES'
  end

  describe 'capture_variables_except' do
    include_examples 'capture variables configuration',
      :capture_variables_except,
      'DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT'
  end
end
