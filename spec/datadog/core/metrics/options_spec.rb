require 'spec_helper'

require 'datadog/core/metrics/ext'
require 'datadog/core/environment/ext'
require 'datadog/core/environment/identity'

require 'datadog/core/metrics/options'

RSpec.describe Datadog::Core::Metrics::Options do
  context 'when included into a class' do
    subject(:instance) { options_class.new }

    let(:options_class) { stub_const('OptionsClass', Class.new { include Datadog::Core::Metrics::Options }) }

    describe '#default_metric_options' do
      subject(:default_metric_options) { instance.default_metric_options }

      it { is_expected.to be_a_kind_of(Hash) }
      it { expect(default_metric_options.frozen?).to be false }

      describe ':tags' do
        subject(:default_tags) { default_metric_options[:tags] }

        it { is_expected.to be_a_kind_of(Array) }
        it { expect(default_tags.frozen?).to be false }

        it 'includes default tags' do
          is_expected.to include(
            "#{Datadog::Core::Metrics::Ext::TAG_LANG}:#{Datadog::Core::Environment::Identity.lang}",
            "#{Datadog::Core::Metrics::Ext::TAG_LANG_INTERPRETER}:#{Datadog::Core::Environment::Identity.lang_interpreter}",
            "#{Datadog::Core::Metrics::Ext::TAG_LANG_VERSION}:#{Datadog::Core::Environment::Identity.lang_version}",
            "#{Datadog::Core::Metrics::Ext::TAG_TRACER_VERSION}:#{Datadog::Core::Environment::Identity.tracer_version}"
          )
        end

        context 'when #env configuration setting' do
          before do
            allow(Datadog.configuration).to receive(:env).and_return(environment)
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to_not include(/\A#{Datadog::Core::Environment::Ext::TAG_ENV}:/o) }
          end

          context 'is defined' do
            let(:environment) { 'my-env' }

            it { is_expected.to include("#{Datadog::Core::Environment::Ext::TAG_ENV}:#{environment}") }
          end
        end

        context 'when Datadog::Environment.version' do
          before do
            allow(Datadog.configuration).to receive(:version).and_return(version)
          end

          context 'is not defined' do
            let(:version) { nil }

            it { is_expected.to_not include(/\A#{Datadog::Core::Environment::Ext::TAG_VERSION}:/o) }
          end

          context 'is defined' do
            let(:version) { 'my-version' }

            it { is_expected.to include("#{Datadog::Core::Environment::Ext::TAG_VERSION}:#{version}") }
          end
        end
      end
    end
  end
end
