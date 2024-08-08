require 'spec_helper'
require 'datadog/core/crashtracking/component'

RSpec.describe Datadog::Core::Crashtracking::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { double('agent_settings') }
  let(:logger) { Logger.new($stdout) }

  describe '.build' do
    let(:tags) { {} }
    let(:agent_base_url) { 'agent_base_url' }
    let(:ld_library_path) { 'ld_library_path' }
    let(:path_to_crashtracking_receiver_binary) { 'path_to_crashtracking_receiver_binary' }

    context 'when all required parameters are provided' do
      it 'creates a new instance of Component and starts it' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings).and_return(tags)
        expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path).and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary).and_return(path_to_crashtracking_receiver_binary)

        component = double('component')
        expect(described_class).to receive(:new).with(
          tags: tags,
          agent_base_url: agent_base_url,
          ld_library_path: ld_library_path,
          path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
          logger: logger
        ).and_return(component)

        expect(component).to receive(:start)

        described_class.build(settings, agent_settings, logger: logger)
      end
    end

    context 'when missing `agent_base_url`' do
      let(:agent_base_url) { nil }

      it 'returns nil' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings).and_return(tags)
        expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path).and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary).and_return(path_to_crashtracking_receiver_binary)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
      end
    end

    context 'when missing `ld_library_path`' do
      let(:ld_library_path) { nil }

      it 'returns nil' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings).and_return(tags)
        expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path).and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary).and_return(path_to_crashtracking_receiver_binary)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
      end
    end

    context 'when missing `path_to_crashtracking_receiver_binary`' do
      let(:path_to_crashtracking_receiver_binary) { nil }

      it 'returns nil' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings).and_return(tags)
        expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path).and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary).and_return(path_to_crashtracking_receiver_binary)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
      end
    end
  end

  describe '#initialize' do
    it 'assigns the provided parameters to instance variables' do
      tags = double('tags')
      agent_base_url = double('agent_base_url')
      ld_library_path = double('ld_library_path')
      path_to_crashtracking_receiver_binary = double('path_to_crashtracking_receiver_binary')

      component = described_class.new(
        tags: tags,
        agent_base_url: agent_base_url,
        ld_library_path: ld_library_path,
        path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
        logger: logger
      )

      expect(component.instance_variable_get(:@tags)).to eq(tags)
      expect(component.instance_variable_get(:@agent_base_url)).to eq(agent_base_url)
      expect(component.instance_variable_get(:@ld_library_path)).to eq(ld_library_path)
      expect(component.instance_variable_get(:@path_to_crashtracking_receiver_binary)).to eq(path_to_crashtracking_receiver_binary)
      expect(component.instance_variable_get(:@logger)).to eq(logger)
    end
  end

  describe '#start' do
    it 'applies the AtForkMonkeyPatch, starts or updates on fork, and resets after fork' do
      component = described_class.new(
        tags: double('tags'),
        agent_base_url: double('agent_base_url'),
        ld_library_path: double('ld_library_path'),
        path_to_crashtracking_receiver_binary: double('path_to_crashtracking_receiver_binary'),
        logger: logger
      )

      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:apply!)
      expect(component).to receive(:start_or_update_on_fork).with(action: :start)
      expect(component).to receive(:reset_after_fork)

      component.start
    end
  end

  describe '#reset_after_fork' do
    xit 'runs the reset logic only once' do
      component = described_class.new(
        tags: double('tags'),
        agent_base_url: double('agent_base_url'),
        ld_library_path: double('ld_library_path'),
        path_to_crashtracking_receiver_binary: double('path_to_crashtracking_receiver_binary'),
        logger: logger
      )

      expect(Datadog::Core::Utils::OnlyOnce).to receive(:new).and_return(double('only_once', run: nil))
      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:at_fork).with(:child).and_yield

      component.reset_after_fork
    end
  end

  describe '#stop' do
    it 'stops the crash tracking' do
      component = described_class.new(
        tags: double('tags'),
        agent_base_url: double('agent_base_url'),
        ld_library_path: double('ld_library_path'),
        path_to_crashtracking_receiver_binary: double('path_to_crashtracking_receiver_binary'),
        logger: logger
      )

      expect(described_class).to receive(:_native_stop)
      expect(logger).to receive(:debug).with('Crash tracking stopped successfully')

      component.stop
    end

    it 'logs an error if stopping the crash tracking fails' do
      component = described_class.new(
        tags: double('tags'),
        agent_base_url: double('agent_base_url'),
        ld_library_path: double('ld_library_path'),
        path_to_crashtracking_receiver_binary: double('path_to_crashtracking_receiver_binary'),
        logger: logger
      )

      error_message = 'Failed to stop crash tracking'
      expect(described_class).to receive(:_native_stop).and_raise(error_message)
      expect(logger).to receive(:error).with("Failed to stop crash tracking: #{error_message}")

      component.stop
    end
  end
end
