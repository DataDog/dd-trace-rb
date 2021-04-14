require 'spec_helper'
require 'ddtrace/runtime/container'

RSpec.describe Datadog::Runtime::Container do
  describe '::descriptor' do
    subject(:descriptor) { described_class.descriptor }

    around do |example|
      # Reset descriptor since it's cached.
      described_class.instance_variable_set(:@descriptor, nil)
      example.run
      described_class.instance_variable_set(:@descriptor, nil)
    end

    context 'when not in a containerized environment' do
      include_context 'non-containerized environment'

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: nil,
          container_id: nil,
          task_uid: nil
        )
      end
    end

    context 'when in a Docker environment' do
      include_context 'Docker environment'

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: 'docker',
          container_id: container_id,
          task_uid: nil
        )
      end
    end

    context 'when in a Kubernetes environment' do
      include_context 'Kubernetes environment'

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: 'kubepods',
          container_id: container_id,
          task_uid: pod_id
        )
      end
    end

    context 'when in a ECS environment' do
      include_context 'ECS environment'

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: 'ecs',
          container_id: container_id,
          task_uid: task_arn
        )
      end
    end

    context 'when in a Fargate 1.3- environment' do
      include_context 'Fargate 1.3- environment'

      it do
        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: 'ecs',
          container_id: container_id,
          task_uid: task_arn
        )
      end
    end

    context 'when in a Fargate 1.4+ environment' do
      include_context 'Fargate 1.4+ environment'

      it do
        # allow(File).to receive(:exist?)

        is_expected.to be_a_kind_of(described_class::Descriptor)
        is_expected.to have_attributes(
          platform: 'ecs',
          container_id: container_id,
          task_uid: nil
        )
      end
    end
  end
end
