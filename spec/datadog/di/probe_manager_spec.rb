require "datadog/di/spec_helper"
require 'datadog/di/probe_manager'
require 'datadog/di/instrumenter'
require 'logger'

class ProbeManagerSpecTestClass; end

RSpec.describe Datadog::DI::ProbeManager do
  di_test

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
  end

  let(:instrumenter) do
    instance_double(Datadog::DI::Instrumenter)
  end

  let(:probe_notification_builder) do
    instance_double(Datadog::DI::ProbeNotificationBuilder)
  end

  let(:probe_notifier_worker) do
    instance_double(Datadog::DI::ProbeNotifierWorker)
  end

  di_logger_double

  let(:probe_repository) do
    Datadog::DI::ProbeRepository.new
  end

  let(:manager) do
    described_class.new(settings, instrumenter, probe_notification_builder, probe_notifier_worker, logger, probe_repository)
  end

  describe '.new' do
    after do
      manager.close
    end

    it 'creates an instance' do
      expect(manager).to be_a(described_class)
    end
  end

  describe '#add_probe' do
    after do
      allow(instrumenter).to receive(:unhook)
      manager.close
    end

    context 'log probe' do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: '3ecfd456-2d7c-4359-a51f-d4cc44141ffe', type: :log, file: 'xx', line_no: 123,
        )
      end

      context 'when probe is installed successfully' do
        it 'returns true and adds probe to the installed probe list' do
          expect(instrumenter).to receive(:hook) do |probe_|
            expect(probe_).to be(probe)
          end

          expect(probe_notification_builder).to receive(:build_installed)
          expect(probe_notifier_worker).to receive(:add_status)

          expect(manager.add_probe(probe)).to be true

          expect(probe_repository.pending_probes.length).to eq 0
          expect(probe_repository.failed_probes.length).to eq 0

          expect(probe_repository.installed_probes.length).to eq 1
          expect(probe_repository.installed_probes["3ecfd456-2d7c-4359-a51f-d4cc44141ffe"]).to be(probe)
        end
      end

      context 'when instrumentation target is missing' do
        it 'returns false and adds probe to the pending probe list' do
          expect(instrumenter).to receive(:hook) do |probe_|
            expect(probe_).to be(probe)
            raise Datadog::DI::Error::DITargetNotDefined
          end

          expect(probe_notification_builder).not_to receive(:build_installed)
          expect(probe_notifier_worker).not_to receive(:add_status)

          expect(manager.add_probe(probe)).to be false

          expect(probe_repository.pending_probes.length).to eq 1
          expect(probe_repository.pending_probes["3ecfd456-2d7c-4359-a51f-d4cc44141ffe"]).to be(probe)

          expect(probe_repository.installed_probes.length).to eq 0
          expect(probe_repository.failed_probes.length).to eq 0
        end
      end

      context 'when there is an exception during instrumentation' do
        it 'logs warning, reports ERROR status, drops probe and reraises the exception' do
          expect_lazy_log(logger, :debug, /error processing probe configuration.*Instrumentation error/)

          expect(instrumenter).to receive(:hook) do |probe_|
            expect(probe_).to be(probe)
            raise "Instrumentation error"
          end

          expect(probe_notification_builder).not_to receive(:build_installed)
          expect(probe_notification_builder).to receive(:build_errored).with(probe, instance_of(RuntimeError)).and_return({status: 'ERROR'})
          expect(probe_notifier_worker).to receive(:add_status).with({status: 'ERROR'}, probe: probe)

          expect do
            manager.add_probe(probe)
          end.to raise_error(RuntimeError, 'Instrumentation error')

          expect(probe_repository.pending_probes.length).to eq 0

          expect(probe_repository.installed_probes.length).to eq 0

          expect(probe_repository.failed_probes.length).to eq 1
          expect(probe_repository.failed_probes[probe.id]).to match(/Instrumentation error/)
        end
      end

      context 'when the probe is requested to be added the second time' do
        it 'does not instrument the second time and reports ERROR status' do
          expect(probe_repository.installed_probes).to be_empty

          # First call
          expect(instrumenter).to receive(:hook)
          expect(probe_notification_builder).to receive(:build_installed)
          expect(probe_notifier_worker).to receive(:add_status)
          manager.add_probe(probe)

          # Second call - reports ERROR status
          expect(instrumenter).not_to receive(:hook)
          expect(probe_notification_builder).not_to receive(:build_installed)
          expect(probe_notification_builder).to receive(:build_errored).with(probe, instance_of(Datadog::DI::Error::AlreadyInstrumented)).and_return({status: 'ERROR'})
          expect(probe_notifier_worker).to receive(:add_status).with({status: 'ERROR'}, probe: probe)
          expect_lazy_log(logger, :debug, /AlreadyInstrumented: Probe with id .* is already in installed probes/)
          expect do
            manager.add_probe(probe)
          end.to raise_error(Datadog::DI::Error::AlreadyInstrumented, /Probe with id .* is already in installed probes/)
        end
      end

      context 'when probe previously failed to install' do
        before do
          probe_repository.add_failed(probe.id, 'RuntimeError: original installation error')
        end

        it 'does not attempt instrumentation again and reports ERROR status' do
          expect_lazy_log(logger, :debug, /error processing probe configuration.*ProbePreviouslyFailed.*original installation error/)

          expect(instrumenter).not_to receive(:hook)
          expect(probe_notification_builder).not_to receive(:build_installed)
          expect(probe_notification_builder).to receive(:build_errored)
            .with(probe, instance_of(Datadog::DI::Error::ProbePreviouslyFailed))
            .and_return({status: 'ERROR'})
          expect(probe_notifier_worker).to receive(:add_status).with({status: 'ERROR'}, probe: probe)

          expect do
            manager.add_probe(probe)
          end.to raise_error(Datadog::DI::Error::ProbePreviouslyFailed, /original installation error/)

          expect(probe_repository.failed_probes.length).to eq 1
          expect(probe_repository.installed_probes).to be_empty
          expect(probe_repository.pending_probes).to be_empty
        end
      end
    end
  end

  describe '#remove_probe' do
    let(:probe) do
      Datadog::DI::Probe.new(
        id: '123', type: :log, file: 'xx', line_no: 123,
      )
    end

    context 'when there are pending probes' do
      before do
        probe_repository.pending_probes[probe.id] = probe
      end

      context 'when id matches a pending probe' do
        it 'removes pending probe' do
          manager.remove_probe('123')

          expect(probe_repository.pending_probes).to eq({})
        end
      end

      context 'when id does not match a pending probe' do
        it 'does not remove the pending probe' do
          manager.remove_probe('555')

          expect(probe_repository.pending_probes).to eq(probe.id => probe)
        end
      end
    end

    context 'when there are installed probes' do
      before do
        probe_repository.installed_probes[probe.id] = probe
      end

      context 'when id matches an installed probe' do
        it 'removes pending probe' do
          expect(instrumenter).to receive(:unhook).with(probe)

          manager.remove_probe('123')

          expect(probe_repository.installed_probes).to eq({})
        end
      end

      context 'when id does not match an installed probe' do
        it 'does not remove the pending probe' do
          expect(instrumenter).not_to receive(:unhook)

          manager.remove_probe('555')

          expect(probe_repository.installed_probes).to eq(probe.id => probe)
        end
      end

      context 'when there is an exception during de-instrumentation' do
        it 'logs warning and keeps probe in installed list' do
          expect(instrumenter).to receive(:unhook).with(probe).and_raise("Deinstrumentation error")

          expect_lazy_log(logger, :debug, /error removing log probe.*Deinstrumentation error/)

          manager.remove_probe('123')

          expect(probe_repository.pending_probes.length).to eq 0

          expect(probe_repository.installed_probes.length).to eq 1
        end
      end

      context 'when there are two probes to be unhooked' do
        let(:probe2) do
          Datadog::DI::Probe.new(
            id: '456', type: :log, file: 'xx', line_no: 123,
          )
        end

        before do
          probe_repository.installed_probes[probe2.id] = probe2
          expect(probe_repository.installed_probes.length).to eq 2
        end

        it 'leaves the second probe installed' do
          expect(instrumenter).to receive(:unhook).with(probe)

          manager.remove_probe('123')

          expect(probe_repository.pending_probes.length).to eq 0

          expect(probe_repository.installed_probes).to eq('456' => probe2)
        end
      end
    end
  end

  describe '#close' do
    let(:trace_point) do
      instance_double(TracePoint)
    end

    it 'disables the trace point' do
      expect(TracePoint).to receive(:new).with(:end).and_return(trace_point)

      manager

      expect(trace_point).to receive(:disable)
      manager.close
    end

    it 'clears hooks' do
      expect(manager).to receive(:clear_hooks)
      manager.close
    end
  end

  describe '#clear_hooks' do
    context 'pending probes' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log,
          type_name: 'foo', method_name: 'bar')
      end

      before do
        probe_repository.pending_probes[probe.id] = probe
      end

      it 'does not unhook' do
        expect(instrumenter).not_to receive(:unhook)

        manager.clear_hooks
      end

      it 'clears pending probes list' do
        expect(instrumenter).not_to receive(:unhook)

        manager.clear_hooks

        expect(probe_repository.pending_probes).to be_empty
      end
    end

    context 'installed probes' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log,
          type_name: 'ProbeManagerSpecTestClass', method_name: 'bar')
      end

      before do
        probe_repository.installed_probes[probe.id] = probe
      end

      it 'unhooks' do
        expect(instrumenter).to receive(:unhook).with(probe)

        manager.clear_hooks
      end

      it 'clears installed probes list' do
        expect(instrumenter).to receive(:unhook).with(probe)

        manager.clear_hooks

        expect(probe_repository.installed_probes).to be_empty
      end
    end
  end

  describe '#install_pending_method_probes' do
    context 'when a class with the same name as target type is defined' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log, type_name: 'ProbeManagerSpecTestClass', method_name: 'bar')
      end

      it 'is invoked' do
        expect(manager).to receive(:install_pending_method_probes) do |cls|
          expect(cls).to be_a(Class)
          expect(cls.name).to eq 'ProbeManagerSpecTestClass'
        end

        manager.reopen
        class ProbeManagerSpecTestClass; end # rubocop:disable Lint/ConstantDefinitionInBlock
      end
    end
  end

  describe '#probe_executed_callback' do
    let(:probe) do
      instance_double(
        Datadog::DI::Probe,
        :id => 'test-probe',
        :type => 'log',
        :location => 'test.rb:42',
        :emitting_notified? => false,
        :emitting_notified= => nil,
      )
    end

    let(:context) do
      instance_double(Datadog::DI::Context, probe: probe)
    end

    it 'queues the snapshot as a Hash' do
      allow(probe_notification_builder).to receive(:build_emitting).and_return({status: 'EMITTING'})
      allow(probe_notification_builder).to receive(:build_executed).and_return({snapshot: 'data'})
      allow(probe_notifier_worker).to receive(:add_status)

      expect(probe_notifier_worker).to receive(:add_snapshot) do |payload|
        expect(payload).to be_a(Hash)
        expect(payload).to eq({snapshot: 'data'})
      end

      manager.probe_executed_callback(context)
    end
  end
end
