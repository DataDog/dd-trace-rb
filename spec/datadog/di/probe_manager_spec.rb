require "datadog/di/spec_helper"
require 'datadog/di/probe'

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

  let(:logger) do
    instance_double(Logger)
  end

  let(:manager) do
    described_class.new(settings, instrumenter, probe_notification_builder, probe_notifier_worker, logger)
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

          expect(manager.pending_probes.length).to eq 0
          expect(manager.failed_probes.length).to eq 0

          expect(manager.installed_probes.length).to eq 1
          expect(manager.installed_probes["3ecfd456-2d7c-4359-a51f-d4cc44141ffe"]).to be(probe)
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

          expect(manager.pending_probes.length).to eq 1
          expect(manager.pending_probes["3ecfd456-2d7c-4359-a51f-d4cc44141ffe"]).to be(probe)

          expect(manager.installed_probes.length).to eq 0
          expect(manager.failed_probes.length).to eq 0
        end
      end

      context 'when there is an exception during instrumentation' do
        it 'logs warning, drops probe and reraises the exception' do
          expect(logger).to receive(:warn) do |msg|
            expect(msg).to match(/Error processing probe configuration.*Instrumentation error/)
          end

          expect(instrumenter).to receive(:hook) do |probe_|
            expect(probe_).to be(probe)
            raise "Instrumentation error"
          end

          expect(probe_notification_builder).not_to receive(:build_installed)
          expect(probe_notifier_worker).not_to receive(:add_status)

          expect do
            manager.add_probe(probe)
          end.to raise_error(RuntimeError, 'Instrumentation error')

          expect(manager.pending_probes.length).to eq 0

          expect(manager.installed_probes.length).to eq 0

          expect(manager.failed_probes.length).to eq 1
          expect(manager.failed_probes[probe.id]).to match(/Instrumentation error/)
        end
      end
    end
  end

  describe '#remove_other_probes' do
    let(:probe) do
      Datadog::DI::Probe.new(
        id: '3ecfd456-2d7c-4359-a51f-d4cc44141ffe', type: :log, file: 'xx', line_no: 123,
      )
    end

    context 'when there are pending probes' do
      before do
        manager.pending_probes[probe.id] = probe
      end

      context 'when pending probe id is in probe ids' do
        it 'does not remove pending probe' do
          manager.remove_other_probes([probe.id])

          expect(manager.pending_probes).to eq(probe.id => probe)
        end
      end

      context 'when pending probe id is not in probe ids' do
        it 'removes pending probe' do
          manager.remove_other_probes(['123'])

          expect(manager.pending_probes).to eq({})
        end
      end
    end

    context 'when there are installed probes' do
      before do
        manager.installed_probes[probe.id] = probe
      end

      context 'when installed probe id is in probe ids' do
        it 'does not remove installed probe' do
          manager.remove_other_probes([probe.id])

          expect(manager.installed_probes).to eq(probe.id => probe)
        end
      end

      context 'when installed probe id is not in probe ids' do
        it 'removes installed probe' do
          expect(instrumenter).to receive(:unhook).with(probe)

          manager.remove_other_probes(['123'])

          expect(manager.installed_probes).to eq({})
        end
      end

      context 'when there is an exception during de-instrumentation' do
        it 'logs warning and keeps probe in installed list' do
          expect(instrumenter).to receive(:unhook).with(probe).and_raise("Deinstrumentation error")

          expect(logger).to receive(:warn) do |msg|
            expect(msg).to match(/Error removing probe.*Deinstrumentation error/)
          end

          manager.remove_other_probes(['123'])

          expect(manager.pending_probes.length).to eq 0

          expect(manager.installed_probes.length).to eq 1
        end

        context 'when there are two probes to be unhooked' do
          let(:probe2) do
            Datadog::DI::Probe.new(
              id: '3ecfd456-2d7c-ffff-a51f-d4cc44141ffe', type: :log, file: 'xx', line_no: 123,
            )
          end

          before do
            manager.installed_probes[probe2.id] = probe2
            expect(manager.installed_probes.length).to eq 2
          end

          it 'logs warning and unhooks the second probe' do
            expect(instrumenter).to receive(:unhook).with(probe).and_raise("Deinstrumentation error")
            expect(instrumenter).to receive(:unhook).with(probe2)

            expect(logger).to receive(:warn) do |msg|
              expect(msg).to match(/Error removing probe.*Deinstrumentation error/)
            end

            manager.remove_other_probes(['123'])

            expect(manager.pending_probes.length).to eq 0

            expect(manager.installed_probes.length).to eq 1
          end
        end
      end
    end
  end

  describe '#close' do
    let(:trace_point) do
      instance_double(TracePoint)
    end

    it 'disables the trace point' do
      expect(TracePoint).to receive(:trace).with(:end).and_return(trace_point)

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
        manager.pending_probes[probe.id] = probe
      end

      it 'does not unhook' do
        expect(instrumenter).not_to receive(:unhook)

        manager.clear_hooks
      end

      it 'clears pending probes list' do
        expect(instrumenter).not_to receive(:unhook)

        manager.clear_hooks

        expect(manager.pending_probes).to be_empty
      end
    end

    context 'installed probes' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log,
          type_name: 'ProbeManagerSpecTestClass', method_name: 'bar')
      end

      before do
        manager.installed_probes[probe.id] = probe
      end

      it 'unhooks' do
        expect(instrumenter).to receive(:unhook).with(probe)

        manager.clear_hooks
      end

      it 'clears installed probes list' do
        expect(instrumenter).to receive(:unhook).with(probe)

        manager.clear_hooks

        expect(manager.installed_probes).to be_empty
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

        class ProbeManagerSpecTestClass; end
      end
    end
  end
end
