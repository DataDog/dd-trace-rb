require 'spec_helper'
require 'support/container_helpers'
require 'datadog/core/environment/cgroup'

# rubocop:disable Layout/LineLength
RSpec.describe Datadog::Core::Environment::Cgroup do
  describe '::entries' do
    subject(:entries) { described_class.entries }

    context 'when the \'/proc/self/cgroup\' file is not present' do
      before do
        expect(Datadog.logger).to_not receive(:error)

        expect(File).to receive(:exist?)
          .with('/proc/self/cgroup')
          .and_return(false)
      end

      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to be_empty
      end
    end

    context 'given a \'/proc/self/cgroup\' file' do
      shared_examples 'parsing cgroup file into an array of entries' do
        it 'returns an array of entries' do
          is_expected.to be_an(Array)
          is_expected.to all(be_a(described_class::Entry))
        end

        it 'parses each entry into an element' do
          is_expected.to have(lines).items
        end
      end

      context 'in a non-containerized environment' do
        include_context 'non-containerized environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a non-containerized environment with VTE' do
        include_context 'non-containerized environment with VTE'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Docker environment' do
        include_context 'Docker environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Docker systemd environment' do
        include_context 'Docker systemd environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Kubernetes environment' do
        include_context 'Kubernetes environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Kubernetes burstable environment' do
        include_context 'Kubernetes burstable environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in an ECS environment' do
        include_context 'ECS environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.3- environment' do
        include_context 'Fargate 1.3- environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.4+ environment' do
        include_context 'Fargate 1.4+ environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.4+ (2-part) environment' do
        include_context 'Fargate 1.4+ (2-part) environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.4+ (2-part short random) environment' do
        include_context 'Fargate 1.4+ (2-part short random) environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.4+ with ECS+docker environment' do
        include_context 'Fargate 1.4+ with ECS+docker environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      # Cgroups v2 contexts
      context 'in a non-containerized v2 environment' do
        include_context 'non-containerized v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Docker v2 environment' do
        include_context 'Docker v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Docker systemd v2 environment' do
        include_context 'Docker systemd v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Kubernetes v2 environment' do
        include_context 'Kubernetes v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Kubernetes burstable v2 environment' do
        include_context 'Kubernetes burstable v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in an ECS v2 environment' do
        include_context 'ECS v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end

      context 'in a Fargate 1.4+ v2 environment' do
        include_context 'Fargate 1.4+ v2 environment'
        include_examples 'parsing cgroup file into an array of entries'
      end
    end
  end

  describe '::parse' do
    subject(:parse) { described_class.parse(entry_line) }

    context 'given a line' do
      context 'that is blank' do
        let(:entry_line) { '' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: nil,
            controllers: nil,
            path: nil,
          )
        end
      end

      context 'with an empty path' do
        let(:entry_line) { '12:freezer:/' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '12',
            controllers: 'freezer',
            path: '/',
          )
        end
      end

      context 'with \'.slice\'' do
        let(:entry_line) { '11:memory:/user.slice' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '11',
            controllers: 'memory',
            path: '/user.slice',
          )
        end
      end

      context 'with comma-separated controllers' do
        let(:entry_line) { '4:cpu,cpuacct:/user.slice' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '4',
            controllers: 'cpu,cpuacct',
            path: '/user.slice',
          )
        end
      end

      context 'with ":" in the path' do
        let(:entry_line) { '5:rdma:/docker/abc:def:ghi' }
        it { is_expected.to be_a_kind_of(described_class::Entry) }
        it do
          is_expected.to have_attributes(
            hierarchy: '5',
            controllers: 'rdma',
            path: '/docker/abc:def:ghi',
          )
        end
      end

      context 'with no group' do
        let(:entry_line) { '0::/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '0',
            controllers: '',
            path: '/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service',
          )
        end
      end

      context 'with \'@\'' do
        let(:entry_line) { '1:name=systemd:/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'name=systemd',
            path: '/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service',
          )
        end
      end

      context 'in Docker format' do
        let(:entry_line) { '13:name=systemd:/docker/3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '13',
            controllers: 'name=systemd',
            path: '/docker/3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860',
          )
        end
      end

      context 'in Kubernetes format' do
        let(:entry_line) { '1:name=systemd:/kubepods/besteffort/pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a/3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'name=systemd',
            path: '/kubepods/besteffort/pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a/3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1',
          )
        end
      end

      context 'in ECS format' do
        let(:entry_line) { '1:blkio:/ecs/haissam-ecs-classic/5a0d5ceddf6c44c1928d367a815d890f/38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'blkio',
            path: '/ecs/haissam-ecs-classic/5a0d5ceddf6c44c1928d367a815d890f/38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce',
          )
        end
      end

      context 'in Fargate format 1.3-' do
        let(:entry_line) { '1:name=systemd:/ecs/55091c13-b8cf-4801-b527-f4601742204d/432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'name=systemd',
            path: '/ecs/55091c13-b8cf-4801-b527-f4601742204d/432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da',
          )
        end
      end

      context 'in Fargate format 1.4+' do
        let(:entry_line) { '1:name=systemd:/ecs/34dc0b5e626f2c5c4c5170e34b10e765-1234567890' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'name=systemd',
            path: '/ecs/34dc0b5e626f2c5c4c5170e34b10e765-1234567890',
          )
        end
      end

      context 'in Fargate format 1.4+ (2-part)' do
        let(:entry_line) { '1:name=systemd:/ecs/34dc0b5e626f2c5c4c5170e34b10e765/34dc0b5e626f2c5c4c5170e34b10e765-1234567890' }

        it { is_expected.to be_a_kind_of(described_class::Entry) }

        it do
          is_expected.to have_attributes(
            hierarchy: '1',
            controllers: 'name=systemd',
            path: '/ecs/34dc0b5e626f2c5c4c5170e34b10e765/34dc0b5e626f2c5c4c5170e34b10e765-1234567890',
          )
        end
      end
    end
  end

  describe '::inode_for' do
    subject(:inode_for) { described_class.inode_for(controllers, path) }

    context 'when path is nil' do
      let(:controllers) { 'memory' }
      let(:path) { nil }

      it { is_expected.to be_nil }
    end

    context 'with comma-separated controllers (co-mounted in cgroup v1)' do
      let(:controllers) { 'cpu,cpuacct' }  # controllers field
      let(:path) { '/user.slice' }              # path field
      let(:expected_path) { '/sys/fs/cgroup/cpu,cpuacct/user.slice' }

      context 'when the cgroup filesystem path exists' do
        let(:inode) { 12345 }

        before do
          allow(File).to receive(:exist?).with(expected_path).and_return(true)
          allow(File).to receive(:stat).with(expected_path).and_return(double(ino: inode))
        end

        it { is_expected.to eq(inode) }

        it 'constructs the correct filesystem path with comma-separated controllers' do
          inode_for
          expect(File).to have_received(:exist?).with(expected_path)
        end
      end

      context 'when the cgroup filesystem path does not exist' do
        before do
          allow(File).to receive(:exist?).with(expected_path).and_return(false)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'with single controller' do
      let(:controllers) { 'memory' }
      let(:path) { '/docker/abc123' }
      let(:expected_path) { '/sys/fs/cgroup/memory/docker/abc123' }

      context 'when the cgroup filesystem path exists' do
        let(:inode) { 67890 }

        before do
          allow(File).to receive(:exist?).with(expected_path).and_return(true)
          allow(File).to receive(:stat).with(expected_path).and_return(double(ino: inode))
        end

        it { is_expected.to eq(inode) }
      end
    end

    context 'with no controller (cgroup v2)' do
      let(:controllers) { '' }
      let(:path) { '/user.slice/user-1000.slice' }
      let(:expected_path) { '/sys/fs/cgroup/user.slice/user-1000.slice' }

      context 'when the cgroup filesystem path exists' do
        let(:inode) { 11111 }

        before do
          allow(File).to receive(:exist?).with(expected_path).and_return(true)
          allow(File).to receive(:stat).with(expected_path).and_return(double(ino: inode))
        end

        it { is_expected.to eq(inode) }

        it 'constructs the correct filesystem path without controller directory' do
          inode_for
          expect(File).to have_received(:exist?).with(expected_path)
        end
      end
    end
  end
end
# rubocop:enable Layout/LineLength
