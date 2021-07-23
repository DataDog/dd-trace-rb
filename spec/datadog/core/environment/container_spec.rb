require 'spec_helper'
require 'datadog/core/environment/container'

RSpec.describe Datadog::Core::Environment::Container do
  describe '::descriptor' do
    subject(:descriptor) { described_class.descriptor }

    around do |example|
      # Reset descriptor since it's cached.
      described_class.instance_variable_set(:@descriptor, nil)
      example.run
      described_class.instance_variable_set(:@descriptor, nil)
    end

    shared_examples_for 'container descriptor' do
      before { expect(Datadog.logger).to_not receive(:error) }

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: platform,
          container_id: container_id,
          task_uid: task_uid
        )
      end
    end

    context 'when in a non-containerized environment' do
      include_context 'non-containerized environment'

      it_behaves_like 'container descriptor' do
        let(:container_id) { nil }
        let(:task_uid) { nil }
      end
    end

    context 'when in a non-containerized environment with VTE' do
      include_context 'non-containerized environment with VTE'

      it_behaves_like 'container descriptor' do
        let(:container_id) { terminal_id }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Docker environment' do
      include_context 'Docker environment'

      it_behaves_like 'container descriptor' do
        let(:task_uid) { nil }
      end
    end

    context 'when in a Kubernetes burstable environment' do
      include_context 'Kubernetes burstable environment'

      it_behaves_like 'container descriptor' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in a Kubernetes environment' do
      include_context 'Kubernetes environment'

      it_behaves_like 'container descriptor' do
        let(:task_uid) { pod_id }
      end
    end

    context 'when in a ECS environment' do
      include_context 'ECS environment'

      it_behaves_like 'container descriptor' do
        let(:task_uid) { task_arn }
      end
    end

    context 'when in a Fargate 1.3- environment' do
      include_context 'Fargate 1.3- environment'

      it_behaves_like 'container descriptor' do
        let(:task_uid) { task_arn }
      end
    end

    context 'when in a Fargate 1.4+ environment' do
      include_context 'Fargate 1.4+ environment'

      it_behaves_like 'container descriptor' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ (2-part) environment' do
      include_context 'Fargate 1.4+ (2-part) environment'

      it_behaves_like 'container descriptor' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ (2-part short random) environment' do
      include_context 'Fargate 1.4+ (2-part short random) environment'

      it_behaves_like 'container descriptor' do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context 'when in a Fargate 1.4+ with ECS+docker environment' do
      include_context 'Fargate 1.4+ with ECS+docker environment'

      it_behaves_like 'container descriptor' do
        let(:container_id) { child_container_id }
        let(:task_uid) { task_arn }
      end
    end
  end
end
