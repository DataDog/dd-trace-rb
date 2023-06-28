require 'stringio'

module ContainerHelpers
  shared_context 'cgroup file' do
    let(:cgroup_file) { StringIO.new }

    before do
      allow(File).to receive(:exist?).and_call_original

      expect(File).to receive(:exist?)
        .with('/proc/self/cgroup')
        .and_return(true)

      allow(File).to receive(:foreach).and_call_original

      allow(File).to receive(:foreach)
        .with('/proc/self/cgroup') do |&block|
          cgroup_file.each { |line| block.call(line) }
        end
    end
  end

  # rubocop:disable Layout/LineLength
  shared_context 'non-containerized environment' do
    include_context 'cgroup file'

    let(:platform) { nil }
    let(:lines) { 13 }

    before do
      cgroup_file.puts '12:hugetlb:/'
      cgroup_file.puts '11:devices:/user.slice'
      cgroup_file.puts '10:pids:/user.slice/user-1000.slice/user@1000.service'
      cgroup_file.puts '9:memory:/user.slice'
      cgroup_file.puts '8:cpuset:/'
      cgroup_file.puts '7:rdma:/'
      cgroup_file.puts '6:freezer:/'
      cgroup_file.puts '5:perf_event:/'
      cgroup_file.puts '4:cpu,cpuacct:/user.slice'
      cgroup_file.puts '3:blkio:/user.slice'
      cgroup_file.puts '2:net_cls,net_prio:/'
      cgroup_file.puts '1:name=systemd:/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service'
      cgroup_file.puts '0::/user.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service'
      cgroup_file.rewind
    end
  end

  shared_context 'non-containerized environment with VTE' do
    include_context 'cgroup file'

    let(:platform) { 'user' }
    let(:terminal_id) { '6fec48c4-1f82-4313-a1c2-29e205a96958' }
    let(:lines) { 13 }

    before do
      cgroup_file.puts '12:hugetlb:/'
      cgroup_file.puts "11:devices:/#{platform}.slice"
      cgroup_file.puts "10:pids:/#{platform}.slice/user-1000.slice/user@1000.service"
      cgroup_file.puts "9:memory:/#{platform}.slice"
      cgroup_file.puts '8:cpuset:/'
      cgroup_file.puts '7:rdma:/'
      cgroup_file.puts '6:freezer:/'
      cgroup_file.puts '5:perf_event:/'
      cgroup_file.puts "4:cpu,cpuacct:/#{platform}.slice"
      cgroup_file.puts "3:blkio:/#{platform}.slice"
      cgroup_file.puts '2:net_cls,net_prio:/'
      cgroup_file.puts "1:name=systemd:/#{platform}.slice/user-1000.slice/user@1000.service/gnome-terminal-server.service"
      cgroup_file.puts "0::/#{platform}.slice/user-1000.slice/user@1000.service/app.slice/app-org.gnome.Terminal.slice/vte-spawn-#{terminal_id}.scope"
      cgroup_file.rewind
    end
  end

  shared_context 'Docker environment' do
    include_context 'cgroup file'

    let(:platform) { 'docker' }
    let(:container_id) { '3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }
    let(:lines) { 13 }

    before do
      cgroup_file.puts "13:name=systemd:/#{platform}/#{container_id}"
      cgroup_file.puts "12:pids:/#{platform}/#{container_id}"
      cgroup_file.puts "11:hugetlb:/#{platform}/#{container_id}"
      cgroup_file.puts "10:net_prio:/#{platform}/#{container_id}"
      cgroup_file.puts "9:perf_event:/#{platform}/#{container_id}"
      cgroup_file.puts "8:net_cls:/#{platform}/#{container_id}"
      cgroup_file.puts "7:freezer:/#{platform}/#{container_id}"
      cgroup_file.puts "6:devices:/#{platform}/#{container_id}"
      cgroup_file.puts "5:memory:/#{platform}/#{container_id}"
      cgroup_file.puts "4:blkio:/#{platform}/#{container_id}"
      cgroup_file.puts "3:cpuacct:/#{platform}/#{container_id}"
      cgroup_file.puts "2:cpu:/#{platform}/#{container_id}"
      cgroup_file.puts "1:cpuset:/#{platform}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Kubernetes environment' do
    include_context 'cgroup file'

    let(:platform) { 'kubepods' }
    let(:container_id) { '3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1' }
    let(:pod_id) { 'pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:perf_event:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "10:pids:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "9:memory:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "8:cpu,cpuacct:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "7:blkio:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "6:cpuset:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "5:devices:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "4:freezer:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "3:net_cls,net_prio:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "2:hugetlb:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "1:name=systemd:/#{platform}/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Kubernetes burstable environment' do
    include_context 'cgroup file'

    let(:platform) { 'kubepods' }
    let(:container_id) { '7b8952daecf4c0e44bbcefe1b5c5ebc7b4839d4eefeccefe694709d3809b6199' }
    let(:pod_id) { 'pod2d3da189_6407_48e3_9ab6_78188d75e609' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:perf_event:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "10:pids:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "9:memory:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "8:cpu,cpuacct:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "7:blkio:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "6:cpuset:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "5:devices:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "4:freezer:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "3:net_cls,net_prio:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "2:hugetlb:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.puts "1:name=systemd:/#{platform}.slice/kubepods-burstable.slice/kubepods-burstable-#{pod_id}.slice/docker-#{container_id}.scope"
      cgroup_file.rewind
    end
  end

  shared_context 'ECS environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    let(:container_id) { '38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce' }
    let(:task_arn) { '5a0d5ceddf6c44c1928d367a815d890f' }
    let(:lines) { 9 }

    before do
      cgroup_file.puts "9:perf_event:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "8:memory:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "7:hugetlb:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "6:freezer:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "5:devices:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "4:cpuset:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "3:cpuacct:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "2:cpu:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "1:blkio:/#{platform}/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate 1.3- environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    let(:container_id) { '432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da' }
    let(:task_arn) { '55091c13-b8cf-4801-b527-f4601742204d' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:hugetlb:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "10:pids:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "9:cpuset:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "8:net_cls,net_prio:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "7:cpu,cpuacct:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "6:perf_event:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "5:freezer:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "4:devices:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "3:blkio:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "2:memory:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.puts "1:name=systemd:/#{platform}/#{task_arn}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate 1.4+ environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    let(:container_id_with_random) { "#{container_id_without_random}-1234567890" }
    let(:container_id_without_random) { '34dc0b5e626f2c5c4c5170e34b10e765' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:hugetlb:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "10:pids:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "9:cpuset:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "8:net_cls,net_prio:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "7:cpu,cpuacct:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "6:perf_event:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "5:freezer:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "4:devices:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "3:blkio:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "2:memory:/#{platform}/#{container_id_with_random}"
      cgroup_file.puts "1:name=systemd:/#{platform}/#{container_id_with_random}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate 1.4+ (2-part) environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    let(:container_id_with_random) { "#{container_id_without_random}-1234567890" }
    let(:container_id_without_random) { '34dc0b5e626f2c5c4c5170e34b10e765' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:hugetlb:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "10:pids:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "9:cpuset:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "8:net_cls,net_prio:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "7:cpu,cpuacct:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "6:perf_event:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "5:freezer:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "4:devices:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "3:blkio:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "2:memory:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "1:name=systemd:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate 1.4+ (2-part short random) environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    # Container random ID is normally 10 characters, but we've seen cases with fewer characters in the wild.
    let(:container_id_with_random) { "#{container_id_without_random}-609015642" }
    let(:container_id_without_random) { 'cef584f232933b25e0c6933d7e86cb34' }
    let(:lines) { 11 }

    before do
      cgroup_file.puts "11:hugetlb:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "10:pids:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "9:cpuset:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "8:net_cls,net_prio:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "7:cpu,cpuacct:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "6:perf_event:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "5:freezer:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "4:devices:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "3:blkio:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "2:memory:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.puts "1:name=systemd:/#{platform}/#{container_id_without_random}/#{container_id_with_random}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate 1.4+ with ECS+docker environment' do
    include_context 'cgroup file'

    let(:platform) { 'ecs' }
    let(:task_arn) { 'c101a02b-a99d-4016-b52d-449e313a8087' }
    let(:host_container_id) { '746a2eb2aa309b64c604f5f798c2df761a92ba9e80ad1948edc5f1c63e2e125e' }
    let(:child_container_id) { '3fb61c869147b933a1c459a87eb11429f640e1600e4c9c7f38a9fe39ecbc5d2a' }
    let(:lines) { 10 }

    before do
      cgroup_file.puts "10:pids:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "9:perf_event:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "8:memory:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "7:hugetlb:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "6:freezer:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "5:devices:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "4:cpuset:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "3:cpuacct:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "2:cpu:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.puts "1:blkio:/#{platform}/#{task_arn}/#{host_container_id}/docker/#{child_container_id}"
      cgroup_file.rewind
    end
  end
end
