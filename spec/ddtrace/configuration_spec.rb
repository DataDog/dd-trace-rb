require 'spec_helper'

require 'ddtrace/patcher'
require 'ddtrace/configuration'

RSpec.describe Datadog::Configuration do
  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::Configuration }) }

    describe '#configure' do
      subject(:configure) { test_class.configure }

      context 'deprecation warning for Ruby 1.9' do
        before do
          # Reset deprecation warning
          if Datadog::Patcher.instance_variable_defined?(:@done_once) \
             && !Datadog::Patcher.instance_variable_get(:@done_once).nil?
            Datadog::Patcher.instance_variable_get(:@done_once).delete(:ruby_19_deprecation_warning)
          end
        end

        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0')
          context 'is raised' do
            it do
              expect(Datadog::Tracer.log).to receive(:warn)
                .with(described_class::RUBY_19_DEPRECATION_WARNING)

              configure
            end
          end
        else
          context 'is not raised' do
            it do
              expect(Datadog::Tracer.log).to_not receive(:warn)
                .with(described_class::RUBY_19_DEPRECATION_WARNING)

              configure
            end
          end
        end
      end
    end
  end
end
