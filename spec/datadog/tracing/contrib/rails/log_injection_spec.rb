require 'datadog/tracing/contrib/rails/log_injection'

RSpec.describe Datadog::Tracing::Contrib::Rails::LogInjection do
  describe '.configure_log_tags' do
    context 'when given `nil` as `log_tags` configuration ' do
      it 'sets an array and adds a proc to the config' do
        expect(Datadog.logger).not_to receive(:warn)

        config = OpenStruct.new(log_tags: nil)

        expect do
          described_class.configure_log_tags(config)
        end.to change { config.log_tags }.from(nil).to(be_an(Array).and(have(1).item))
      end
    end

    context 'when given an array as `log_tags` configuration ' do
      it 'adds a proc to the config' do
        expect(Datadog.logger).not_to receive(:warn)

        config = OpenStruct.new(log_tags: [])

        expect do
          described_class.configure_log_tags(config)
        end.to change { config.log_tags }.from([]).to(be_an(Array).and(have(1).item))
      end
    end

    context 'when given a hash as `log_tags` configuration ' do
      it 'deos not change the configuration' do
        expect(Datadog.logger).not_to receive(:warn)

        config = OpenStruct.new(log_tags: {})

        expect do
          described_class.configure_log_tags(config)
        end.not_to(change { config.log_tags })
      end
    end

    context 'when given a string as `log_tags` configuration ' do
      it 'deos not change the configuration and warn about the error' do
        expect(Datadog.logger).to receive(:warn)

        config = OpenStruct.new(log_tags: 'misconfigured with a string')

        expect do
          described_class.configure_log_tags(config)
        end.not_to(change { config.log_tags })
      end
    end
  end
end
