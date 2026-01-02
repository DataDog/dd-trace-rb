require 'spec_helper'
require 'support/container_helpers'
require 'datadog/core/environment/container'

RSpec.describe Datadog::Core::Environment::Container do
  around do |example|
    described_class.remove_instance_variable(:@entry) if described_class.instance_variable_defined?(:@entry)
    example.run
    described_class.remove_instance_variable(:@entry) if described_class.instance_variable_defined?(:@entry)
  end

  describe '::entry' do
    subject(:entry) { described_class.entry }

    shared_examples_for 'container entry' do
      before { expect(Datadog.logger).to_not receive(:error) }

      it do
        is_expected.to be_a_kind_of(described_class::Entry)
        is_expected.to have_attributes(
          platform: platform,
          container_id: container_id,
          task_uid: task_uid
        )
      end
    end

    context 'when in a non-containerized environment' do
      include_context 'non-containerized environment'

      it_behaves_like 'container entry' do
        let(:container_id) { nil }
        let(:task_uid) { nil }
      end
    end

    context 'when in a non-containerized environment with VTE' do
      include_context 'non-containerized environment with VTE'

      it_behaves_like 'container entry' do
        let(:container_id) { terminal_id }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Docker environment' do
      include_context 'Docker environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { nil }
      end
    end

    context 'when in a Docker systemd environment' do
      include_context 'Docker systemd environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { nil }
      end
    end

    context 'when in a Kubernetes burstable environment' do
      include_context 'Kubernetes burstable environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in a Kubernetes environment' do
      include_context 'Kubernetes environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in a ECS environment' do
      include_context 'ECS environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { task_arn }
      end
    end

    context 'when in a Fargate 1.3- environment' do
      include_context 'Fargate 1.3- environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { task_arn }
      end
    end

    context 'when in a Fargate 1.4+ environment' do
      include_context 'Fargate 1.4+ environment'

      it_behaves_like 'container entry' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ (2-part) environment' do
      include_context 'Fargate 1.4+ (2-part) environment'

      it_behaves_like 'container entry' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ (2-part short random) environment' do
      include_context 'Fargate 1.4+ (2-part short random) environment'

      it_behaves_like 'container entry' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ with ECS+docker environment' do
      include_context 'Fargate 1.4+ with ECS+docker environment'

      it_behaves_like 'container entry' do
        let(:container_id) { child_container_id }
        let(:task_uid) { task_arn }
      end
    end

    # Cgroups v2 tests
    context 'when in a non-containerized v2 environment' do
      include_context 'non-containerized v2 environment'

      it_behaves_like 'container entry' do
        let(:container_id) { nil }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Docker v2 environment' do
      include_context 'Docker v2 environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { nil }
      end
    end

    context 'when in a Docker systemd v2 environment' do
      include_context 'Docker systemd v2 environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { nil }
      end
    end

    context 'when in a Kubernetes v2 environment' do
      include_context 'Kubernetes v2 environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in a Kubernetes burstable v2 environment' do
      include_context 'Kubernetes burstable v2 environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in an ECS v2 environment' do
      include_context 'ECS v2 environment'

      it_behaves_like 'container entry' do
        let(:task_uid) { task_arn }
      end
    end

    context 'when in a Fargate 1.4+ v2 environment' do
      include_context 'Fargate 1.4+ v2 environment'

      it_behaves_like 'container entry' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when parsing cgroup entries raises an error' do
      before do
        allow(Datadog.logger).to receive(:debug)
        allow(Datadog::Core::Environment::Cgroup).to receive(:entries).and_raise(StandardError, 'Test error')
      end

      it 'logs the error and returns an empty entry' do
        entry = described_class.entry
        expect(entry).to be_a_kind_of(described_class::Entry)
        expect(entry.platform).to be_nil
        expect(entry.container_id).to be_nil
        expect(entry.task_uid).to be_nil
        expect(entry.inode).to be_nil
        expect(Datadog.logger).to have_received(:debug) do |msg|
          expect(msg).to match(/Error while reading container entry/)
        end
      end
    end
  end

  describe '::entity_id' do
    subject(:entity_id) { described_class.entity_id }

    context 'when container_id is present' do
      include_context 'Docker environment'

      it 'returns entity_id with ci- prefix' do
        expect(entity_id).to eq("ci-#{container_id}")
      end
    end

    context 'when only inode is present (no container_id)' do
      before do
        allow(described_class).to receive(:container_id).and_return(nil)
        allow(described_class).to receive(:inode).and_return(12345)
      end

      it 'returns entity_id with in- prefix' do
        expect(entity_id).to eq('in-12345')
      end
    end

    context 'when neither container_id nor inode is present' do
      include_context 'non-containerized environment'

      it 'returns nil' do
        expect(entity_id).to be_nil
      end
    end
  end

  describe '::external_env' do
    subject(:external_env) { described_class.external_env }

    context 'when configuration returns a string' do
      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return('provided-by-container-runner')
      end

      it 'returns the configured value' do
        expect(external_env).to eq('provided-by-container-runner')
      end
    end

    context 'when configuration returns nil' do
      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(nil)
      end

      it 'returns nil' do
        expect(external_env).to be_nil
      end
    end
  end

  describe '::to_headers' do
    subject(:headers) { described_class.to_headers }

    context 'when container headers and external_env are both present' do
      include_context 'Docker environment'

      let(:external_env_value) { 'provided-by-container-runner' }

      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(external_env_value)
      end

      it 'includes all headers' do
        expect(headers).to include(
          'Datadog-Container-ID' => container_id,
          'Datadog-Entity-ID' => "ci-#{container_id}",
          'Datadog-External-Env' => external_env_value
        )
      end
    end

    context 'when container_id is nil and external_env is nil' do
      include_context 'non-containerized environment'

      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(nil)
      end

      it 'returns empty hash (all nil values compacted)' do
        expect(headers).to eq({})
      end
    end
  end

  describe '::running_on_host?' do
    subject(:running_on_host) { described_class.running_on_host? }

    around do |example|
      described_class.remove_instance_variable(:@running_on_host) if described_class.instance_variable_defined?(:@running_on_host)
      example.run
      described_class.remove_instance_variable(:@running_on_host) if described_class.instance_variable_defined?(:@running_on_host)
    end

    context 'when File.stat raises an error' do
      before do
        allow(Datadog.logger).to receive(:debug)
        allow(File).to receive(:exist?).with('/proc/self/ns/cgroup').and_return(true)
        allow(File).to receive(:stat).with('/proc/self/ns/cgroup').and_raise(StandardError, 'Test error')
      end

      it 'logs the error and returns false' do
        is_expected.to be(false)
        expect(Datadog.logger).to have_received(:debug) do |msg|
          expect(msg).to match(/Error while checking cgroup namespace/)
        end
      end
    end
  end
end
