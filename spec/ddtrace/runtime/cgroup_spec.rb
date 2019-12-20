# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/cgroup'

# rubocop:disable Metrics/LineLength
RSpec.describe Datadog::Runtime::Cgroup do
  describe '::descriptors' do
    subject(:descriptors) { described_class.descriptors }

    context 'when the \'/proc/self/cgroup\' file is not present' do
      before do
        expect(File).to receive(:exist?)
          .with('/proc/self/cgroup')
          .and_return(false)

        expect(Datadog::Logger.log).to_not receive(:error)
      end

      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to be_empty
      end
    end

    context 'given a \'/proc/self/cgroup\' file' do
      context 'which raises an error when opened' do
        include_context 'non-containerized environment'

        let(:error) { stub_const('TestError', Class.new(StandardError)) }

        before do
          expect(File).to receive(:open)
            .with('/proc/self/cgroup')
            .and_raise(error)

          expect(Datadog::Logger.log).to receive(:error) do |msg|
            expect(msg).to match(/Error while parsing cgroup./)
          end
        end

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to be_empty
        end
      end

      context 'in a non-containerized environment' do
        include_context 'non-containerized environment'

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to have(13).items
          is_expected.to include(be_a_kind_of(described_class::Descriptor))
        end
      end

      context 'in a Docker environment' do
        include_context 'Docker environment'

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to have(13).items
          is_expected.to include(be_a_kind_of(described_class::Descriptor))
        end
      end

      context 'in a Kubernetes environment' do
        include_context 'Kubernetes environment'

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to have(11).items
          is_expected.to include(be_a_kind_of(described_class::Descriptor))
        end
      end

      context 'in an ECS environment' do
        include_context 'ECS environment'

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to have(9).items
          is_expected.to include(be_a_kind_of(described_class::Descriptor))
        end
      end

      context 'in a Fargate environment' do
        include_context 'Fargate environment'

        it do
          is_expected.to be_a_kind_of(Array)
          is_expected.to have(11).items
          is_expected.to include(be_a_kind_of(described_class::Descriptor))
        end
      end
    end
  end

  describe '::parse' do
    subject(:parse) { described_class.parse(line) }

    context 'given a line' do
      context 'that is blank' do
        let(:line) { '' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: nil,
            groups: nil,
            path: nil,
            controllers: nil
          )
        end
      end

      context 'with an empty path' do
        let(:line) { '12:freezer:/' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '12',
            groups: 'freezer',
            path: '/',
            controllers: ['freezer']
          )
        end
      end

      context 'with \'.slice\'' do
        let(:line) { '11:memory:/user.slice' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '11',
            groups: 'memory',
            path: '/user.slice',
            controllers: ['memory']
          )
        end
      end

      context 'with no group' do
        let(:line) { '0::/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '0',
            groups: '',
            path: '/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service',
            controllers: []
          )
        end
      end

      context 'with \'@\'' do
        let(:line) { '1:name=systemd:/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '1',
            groups: 'name=systemd',
            path: '/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service',
            controllers: ['name=systemd']
          )
        end
      end

      context 'in Docker format' do
        let(:line) { '13:name=systemd:/docker/3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '13',
            groups: 'name=systemd',
            path: '/docker/3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860',
            controllers: ['name=systemd']
          )
        end
      end

      context 'in Kubernetes format' do
        let(:line) { '1:name=systemd:/kubepods/besteffort/pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a/3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '1',
            groups: 'name=systemd',
            path: '/kubepods/besteffort/pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a/3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1',
            controllers: ['name=systemd']
          )
        end
      end

      context 'in ECS format' do
        let(:line) { '1:blkio:/ecs/haissam-ecs-classic/5a0d5ceddf6c44c1928d367a815d890f/38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '1',
            groups: 'blkio',
            path: '/ecs/haissam-ecs-classic/5a0d5ceddf6c44c1928d367a815d890f/38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce',
            controllers: ['blkio']
          )
        end
      end

      context 'in Fargate format' do
        let(:line) { '1:name=systemd:/ecs/55091c13-b8cf-4801-b527-f4601742204d/432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da' }
        it { is_expected.to be_a_kind_of(described_class::Descriptor) }
        it do
          is_expected.to have_attributes(
            id: '1',
            groups: 'name=systemd',
            path: '/ecs/55091c13-b8cf-4801-b527-f4601742204d/432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da',
            controllers: ['name=systemd']
          )
        end
      end
    end
  end
end
