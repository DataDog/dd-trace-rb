require 'ddtrace'

RSpec.describe Datadog::Initialization do
  subject(:initialization) { described_class.new(Datadog) }

  context '#initialize!' do
    subject(:initialize!) { initialization.initialize! }

    it 'invokes initialization steps' do
      expect(initialization).to receive(:start_life_cycle)

      # DEV: Code responsible for displaying a deprecation warning for a
      # deprecated version of Ruby.
      # expect(initialization).to receive(:ruby_deprecation_warning)

      initialize!
    end
  end

  context '#start_life_cycle' do
    subject(:start_life_cycle) { initialization.start_life_cycle }

    it 'configures ddtrace' do
      expect(Datadog).to receive(:start!)

      start_life_cycle
    end
  end

  # DEV: Code responsible for displaying a deprecation warning for a
  # deprecated version of Ruby.
  #
  # context '#ruby_deprecation_warning' do
  #   subject(:ruby_deprecation_warning) { initialization.ruby_deprecation_warning }
  #
  #   context 'with a deprecated Ruby version' do
  #     before { skip unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1') }
  #
  #     it 'emits deprecation warning once' do
  #       expect(Datadog.logger).to receive(:warn)
  #                                   .with(/Support for Ruby versions < 2\.1 in dd-trace-rb is DEPRECATED/).once
  #
  #       ruby_deprecation_warning
  #     end
  #   end
  #
  #   context 'with a supported Ruby version' do
  #     before { skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1') }
  #
  #     it 'emits no warnings' do
  #       expect(Datadog.logger).to_not receive(:warn)
  #
  #       ruby_deprecation_warning
  #     end
  #   end
  # end
end

