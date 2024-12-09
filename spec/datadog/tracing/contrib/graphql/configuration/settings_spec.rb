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
end
