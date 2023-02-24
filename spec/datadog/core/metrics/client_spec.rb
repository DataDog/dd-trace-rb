require 'spec_helper'

require 'datadog/statsd'

require 'datadog/core/metrics/client'

RSpec.describe Datadog::Core::Metrics::Client do
  include_context 'metrics'

  subject(:metrics) { described_class.new(**options) }
  after { metrics.close }

  let(:options) { { statsd: statsd } }

  it { is_expected.to have_attributes(statsd: statsd) }

  shared_examples_for 'missing value arg' do
    it 'logs an error without raising' do
      expect(Datadog.logger).to receive(:error)
      expect { subject }.to_not raise_error
    end
  end

  describe '#initialize' do
    before do
      # NOTE: allow_any_instace_of is needed as when we run this no metrics instance has been created yet (and we
      # don't want it to be created as the nested contexts still need to change the arguments to the call to new)
      allow_any_instance_of(described_class).to receive(:supported?).and_return(statsd_supported)
    end

    context 'when a supported version of statsd is installed' do
      let(:statsd_supported) { true }

      context 'when no statsd instance is provided' do
        let(:options) { {} }

        after do
          metrics.close
        end

        it 'creates a new instance' do
          expect(metrics.statsd).to_not be nil
        end
      end

      context 'when a statsd instance is provided' do
        let(:statsd) { instance_double(Datadog::Statsd) }
        let(:options) { { statsd: statsd } }

        it 'uses the provided instance' do
          expect(metrics.statsd).to be statsd
        end
      end
    end

    context 'when statsd is either not installed, or an unsupported version is installed' do
      let(:statsd_supported) { false }

      context 'when no statsd instance is provided' do
        let(:options) { {} }

        it 'does not create a new instance' do
          expect(metrics.statsd).to be nil
        end
      end

      context 'when a statsd instance is provided' do
        let(:options) { { statsd: statsd } }

        before do
          described_class.const_get('IGNORED_STATSD_ONLY_ONCE').send(:reset_ran_once_state_for_tests)
          allow(Datadog.logger).to receive(:warn)
        end

        it 'does not use the provided instance' do
          expect(metrics.statsd).to be nil
        end

        it 'logs a warning' do
          expect(Datadog.logger).to receive(:warn).with(/Ignoring .* statsd instance/)

          metrics
        end
      end
    end
  end

  describe '#supported?' do
    subject(:supported?) { metrics.supported? }

    context 'when the dogstatsd gem' do
      before do
        allow(Gem.loaded_specs).to receive(:[])
          .with('dogstatsd-ruby')
          .and_return(spec)

        stub_const 'Datadog::Statsd::VERSION', nil
      end

      context 'is not loaded' do
        let(:spec) { nil }

        it { is_expected.to be false }
      end

      context 'is loaded' do
        let(:spec) { instance_double(Gem::Specification, version: version) }

        context 'with version < 3.3.0' do
          let(:version) { Gem::Version.new('3.2.9') }

          it { is_expected.to be false }
        end

        context 'with version 3.3.0' do
          let(:version) { Gem::Version.new('3.3.0') }

          it { is_expected.to be true }
        end

        context 'with incompatible 5.x version' do
          let(:version) { Gem::Version.new('5.2.0') }

          it { is_expected.to be false }
        end

        context 'with compatible 5.x version' do
          let(:version) { Gem::Version.new('5.3.0') }

          it { is_expected.to be true }
        end
      end

      context 'is loaded but ruby is not using rubygems' do
        before do
          stub_const 'Datadog::Statsd::VERSION', gem_version_number
        end

        let(:spec) { nil }

        context 'with version < 3.3.0' do
          let(:gem_version_number) { '3.2.9' }

          it { is_expected.to be false }
        end

        context 'with version 3.3.0' do
          let(:gem_version_number) { '3.3.0' }

          it { is_expected.to be true }
        end

        context 'with incompatible 5.x version' do
          let(:gem_version_number) { '5.2.0' }

          it { is_expected.to be false }
        end

        context 'with compatible 5.x version' do
          let(:gem_version_number) { '5.3.0' }

          it { is_expected.to be true }
        end
      end
    end
  end

  describe '#enabled?' do
    subject(:enabled) { metrics.enabled? }

    context 'by default' do
      it { is_expected.to be true }
    end

    context 'when initialized as enabled' do
      let(:options) { super().merge(enabled: true) }

      it { is_expected.to be true }
    end

    context 'when initialized as disabled' do
      let(:options) { super().merge(enabled: false) }

      it { is_expected.to be false }
    end
  end

  describe '#enabled=' do
    subject(:enabled) { metrics.enabled? }

    before { metrics.enabled = status }

    context 'is given true' do
      let(:status) { true }

      it { is_expected.to be true }
    end

    context 'is given false' do
      let(:status) { false }

      it { is_expected.to be false }
    end

    context 'is given nil' do
      let(:status) { nil }

      it { is_expected.to be false }
    end
  end

  describe '#default_hostname' do
    subject(:default_hostname) { metrics.default_hostname }

    context 'when environment variable is' do
      context 'set' do
        let(:value) { 'my-hostname' }

        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST => value) do
            example.run
          end
        end

        it { is_expected.to eq(value) }
      end

      context 'not set' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST => nil) do
            example.run
          end
        end

        it { is_expected.to eq(Datadog::Core::Metrics::Ext::DEFAULT_HOST) }
      end
    end
  end

  describe '#default_port' do
    subject(:default_port) { metrics.default_port }

    context 'when environment variable is' do
      context 'set' do
        let(:value) { '1234' }

        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Metrics::ENV_DEFAULT_PORT => value) do
            example.run
          end
        end

        it { is_expected.to eq(value.to_i) }
      end

      context 'not set' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Metrics::ENV_DEFAULT_PORT => nil) do
            example.run
          end
        end

        it { is_expected.to eq(Datadog::Core::Metrics::Ext::DEFAULT_PORT) }
      end
    end
  end

  describe '#default_statsd_client' do
    subject(:default_statsd_client) { metrics.default_statsd_client }

    let(:statsd_client) { instance_double(Datadog::Statsd) }
    let(:options) do
      # This test is run with both ~> 4.0 and latest dogstatsd-ruby.
      if Gem::Version.new(Datadog::Statsd::VERSION) >= Gem::Version.new('5.3.0')
        { single_thread: true }
      else
        {}
      end
    end

    before do
      expect(Datadog::Statsd).to receive(:new)
        .with(metrics.default_hostname, metrics.default_port, **options)
        .and_return(statsd_client)
    end

    it { is_expected.to be(statsd_client) }

    context 'with Datadog::Statsd not loaded' do
      before do
        const = Datadog::Statsd
        hide_const('Datadog::Statsd')

        expect(metrics).to receive(:require).with('datadog/statsd') do
          stub_const('Datadog::Statsd', const)
        end
      end

      it 'loads Datadog::Statsd library' do
        is_expected.to be(statsd_client)
      end
    end
  end

  describe '#configure' do
    subject(:configure) { metrics.configure(configure_options) }

    context 'given options including' do
      context ':statsd' do
        let(:configure_options) { { statsd: custom_statsd } }
        let(:custom_statsd) { instance_double(Datadog::Statsd) }

        it { expect { configure }.to change { metrics.statsd }.from(statsd).to(custom_statsd) }
      end

      context ':enabled' do
        let(:configure_options) { { enabled: enabled } }

        context 'as true' do
          let(:enabled) { true }

          before { configure }

          it { expect(metrics.enabled?).to be(true) }
        end

        context 'as false' do
          let(:enabled) { false }

          before { configure }

          it { expect(metrics.enabled?).to be(false) }
        end
      end
    end
  end

  describe '#send_stats?' do
    subject(:send_stats?) { metrics.send_stats? }

    context 'when disabled' do
      before { metrics.enabled = false }

      it { is_expected.to be(false) }
    end

    context 'when enabled' do
      context 'and Statsd' do
        context 'is initialized' do
          let(:custom_statsd) { instance_double(Datadog::Statsd) }

          before { metrics.configure(statsd: custom_statsd) }

          it { is_expected.to be(true) }
        end

        context 'is nil' do
          before { metrics.configure(statsd: nil) }

          it { is_expected.to be(false) }
        end
      end
    end
  end

  describe '#count' do
    subject(:count) { metrics.count(stat, value, stat_options) }

    let(:stat) { :foo }
    let(:value) { 100 }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { count }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_count_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        context 'that does not yield args' do
          subject(:count) { metrics.count(stat) {} }

          it_behaves_like 'missing value arg'
        end

        context 'that yields args' do
          subject(:count) { metrics.count(stat) { [value, stat_options] } }

          let(:stat_options) { {} }

          before { count }

          it { expect(statsd).to have_received_count_metric(stat) }
        end
      end

      context 'and given no options' do
        before { expect { count }.to_not raise_error }

        it { expect(statsd).to have_received_count_metric(stat) }
      end

      context 'and given options' do
        before { expect { count }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }

          it { expect(statsd).to have_received_count_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }

          it { expect(statsd).to have_received_count_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }

          it { expect(statsd).to have_received_count_metric(stat, kind_of(Numeric), stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }

            it { expect(statsd).to have_received_count_metric(stat, kind_of(Numeric), stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before do
          expect(statsd).to receive(:count).and_raise(StandardError)
          expect(Datadog.logger).to receive(:error)
        end

        it { expect { count }.to_not raise_error }
      end
    end
  end

  describe '#distribution' do
    subject(:distribution) { metrics.distribution(stat, value, stat_options) }

    let(:stat) { :foo }
    let(:value) { 100 }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { distribution }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_distribution_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        context 'that does not yield args' do
          subject(:distribution) { metrics.distribution(stat) {} }

          it_behaves_like 'missing value arg'
        end

        context 'that yields args' do
          subject(:distribution) { metrics.distribution(stat) { [value, stat_options] } }

          let(:stat_options) { {} }

          before { distribution }

          it { expect(statsd).to have_received_distribution_metric(stat) }
        end
      end

      context 'and given no options' do
        before { expect { distribution }.to_not raise_error }

        it { expect(statsd).to have_received_distribution_metric(stat) }
      end

      context 'and given options' do
        before { expect { distribution }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }

          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }

          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }

          it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }

            it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before do
          expect(statsd).to receive(:distribution).and_raise(StandardError)
          expect(Datadog.logger).to receive(:error)
        end

        it { expect { distribution }.to_not raise_error }
      end
    end
  end

  describe '#gauge' do
    subject(:gauge) { metrics.gauge(stat, value, stat_options) }

    let(:stat) { :foo }
    let(:value) { 100 }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { gauge }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_gauge_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        context 'that does not yield args' do
          subject(:gauge) { metrics.gauge(stat) {} }

          it_behaves_like 'missing value arg'
        end

        context 'that yields args' do
          subject(:gauge) { metrics.gauge(stat) { [value, stat_options] } }

          let(:stat_options) { {} }

          before { gauge }

          it { expect(statsd).to have_received_gauge_metric(stat) }
        end
      end

      context 'and given no options' do
        before { expect { gauge }.to_not raise_error }

        it { expect(statsd).to have_received_gauge_metric(stat) }
      end

      context 'and given options' do
        before { expect { gauge }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }

          it { expect(statsd).to have_received_gauge_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }

          it { expect(statsd).to have_received_gauge_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }

          it { expect(statsd).to have_received_gauge_metric(stat, kind_of(Numeric), stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }

            it { expect(statsd).to have_received_gauge_metric(stat, kind_of(Numeric), stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before do
          expect(statsd).to receive(:gauge).and_raise(StandardError)
          expect(Datadog.logger).to receive(:error)
        end

        it { expect { gauge }.to_not raise_error }
      end
    end
  end

  describe '#increment' do
    subject(:increment) { metrics.increment(stat, stat_options) }

    let(:stat) { :foo }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { increment }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_increment_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        context 'that yields args' do
          subject(:increment) { metrics.increment(stat) { stat_options } }

          let(:stat_options) { {} }

          before { increment }

          it { expect(statsd).to have_received_increment_metric(stat) }
        end
      end

      context 'and given no options' do
        before { expect { increment }.to_not raise_error }

        it { expect(statsd).to have_received_increment_metric(stat) }
      end

      context 'and given options' do
        before { expect { increment }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }

          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }

          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'that contain :by' do
          let(:stat_options) { { by: count } }
          let(:count) { 1 }

          it { expect(statsd).to have_received_increment_metric(stat, stat_options) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }

          it { expect(statsd).to have_received_increment_metric(stat, stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }

            it { expect(statsd).to have_received_increment_metric(stat, stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before do
          expect(statsd).to receive(:increment).and_raise(StandardError)
          expect(Datadog.logger).to receive(:error)
        end

        it { expect { increment }.to_not raise_error }
      end
    end
  end

  describe '#time' do
    subject(:time) { metrics.time(stat, stat_options, &block) }

    let(:stat) { :foo }
    let(:stat_options) { nil }
    let(:block) { proc {} }

    context 'when #statsd is nil' do
      before do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { time }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_time_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        it { expect { |b| metrics.time(stat, &b) }.to yield_control }

        context 'which raises an error' do
          let(:block) { proc { raise error } }
          let(:error) { RuntimeError.new }
          # Expect the given block to raise its errors through

          it { expect { time }.to raise_error(error) }
        end
      end

      context 'and given no options' do
        before { expect { time }.to_not raise_error }

        it { expect(statsd).to have_received_time_metric(stat) }
      end

      context 'and given options' do
        before { expect { time }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }

          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }

          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }

          it { expect(statsd).to have_received_time_metric(stat, stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }

            it { expect(statsd).to have_received_time_metric(stat, stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before do
          expect(statsd).to receive(:distribution).and_raise(StandardError)
          expect(Datadog.logger).to receive(:error)
        end

        it { expect { time }.to_not raise_error }
      end
    end
  end

  describe '#send_metrics' do
    subject(:send_metrics) { metrics.send_metrics(metrics_list) }

    context 'given an Array of Metrics' do
      let(:metrics_list) do
        [
          Datadog::Core::Metrics::Metric.new(:distribution, dist_name, dist_value, dist_options),
          Datadog::Core::Metrics::Metric.new(:increment, inc_name, nil, inc_options)
        ]
      end

      let(:dist_name) { 'my-dist' }
      let(:dist_value) { 1 }
      let(:dist_options) { { dist: true } }
      let(:inc_name) { 'my-incr' }
      let(:inc_options) { { incr: true } }

      before do
        allow(metrics).to receive(:distribution)
        allow(metrics).to receive(:increment)
      end

      it 'sends each metric' do
        send_metrics

        expect(metrics).to have_received(:distribution)
          .with(dist_name, dist_value, dist_options)

        expect(metrics).to have_received(:increment)
          .with(inc_name, inc_options)
      end
    end
  end

  describe '#close' do
    subject(:close) { metrics.close }

    context 'with a closeable statsd instance' do
      let(:statsd) { instance_double(Datadog::Statsd, close: nil) }

      it 'closes statsd' do
        close

        expect(statsd).to have_received(:close)
      end
    end

    context 'without a non-closeable statsd instance' do
      let(:statsd) { double }

      it 'does not call nonexistent method #close' do
        close
      end
    end
  end
end
