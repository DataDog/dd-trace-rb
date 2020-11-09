require 'stringio'

# rubocop:disable Metrics/ModuleLength
module ContainerHelpers
  def uuid_regex
    /[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/
  end

  shared_context 'cgroup file' do
    let(:cgroup_file) { StringIO.new }

    before do
      expect(File).to receive(:exist?)
        .with('/proc/self/cgroup')
        .and_return(true)

      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open)
        .with('/proc/self/cgroup')
        .and_return(cgroup_file)
    end
  end

  shared_context 'non-containerized environment' do
    include_context 'cgroup file'

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

  shared_context 'Docker environment' do
    include_context 'cgroup file'

    let(:container_id) { '3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }

    before do
      cgroup_file.puts "13:name=systemd:/docker/#{container_id}"
      cgroup_file.puts "12:pids:/docker/#{container_id}"
      cgroup_file.puts "11:hugetlb:/docker/#{container_id}"
      cgroup_file.puts "10:net_prio:/docker/#{container_id}"
      cgroup_file.puts "9:perf_event:/docker/#{container_id}"
      cgroup_file.puts "8:net_cls:/docker/#{container_id}"
      cgroup_file.puts "7:freezer:/docker/#{container_id}"
      cgroup_file.puts "6:devices:/docker/#{container_id}"
      cgroup_file.puts "5:memory:/docker/#{container_id}"
      cgroup_file.puts "4:blkio:/docker/#{container_id}"
      cgroup_file.puts "3:cpuacct:/docker/#{container_id}"
      cgroup_file.puts "2:cpu:/docker/#{container_id}"
      cgroup_file.puts "1:cpuset:/docker/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Kubernetes environment' do
    include_context 'cgroup file'

    let(:container_id) { '3e74d3fd9db4c9dd921ae05c2502fb984d0cde1b36e581b13f79c639da4518a1' }
    let(:pod_id) { 'pod3d274242-8ee0-11e9-a8a6-1e68d864ef1a' }

    before do
      cgroup_file.puts "11:perf_event:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "10:pids:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "9:memory:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "8:cpu,cpuacct:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "7:blkio:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "6:cpuset:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "5:devices:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "4:freezer:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "3:net_cls,net_prio:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "2:hugetlb:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.puts "1:name=systemd:/kubepods/besteffort/#{pod_id}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'ECS environment' do
    include_context 'cgroup file'

    let(:container_id) { '38fac3e99302b3622be089dd41e7ccf38aff368a86cc339972075136ee2710ce' }
    let(:task_arn) { '5a0d5ceddf6c44c1928d367a815d890f' }

    before do
      cgroup_file.puts "9:perf_event:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "8:memory:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "7:hugetlb:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "6:freezer:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "5:devices:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "4:cpuset:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "3:cpuacct:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "2:cpu:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.puts "1:blkio:/ecs/haissam-ecs-classic/#{task_arn}/#{container_id}"
      cgroup_file.rewind
    end
  end

  shared_context 'Fargate environment' do
    include_context 'cgroup file'

    let(:container_id) { '432624d2150b349fe35ba397284dea788c2bf66b885d14dfc1569b01890ca7da' }
    let(:task_arn) { '55091c13-b8cf-4801-b527-f4601742204d' }

    before do
      cgroup_file.puts "11:hugetlb:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "10:pids:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "9:cpuset:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "8:net_cls,net_prio:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "7:cpu,cpuacct:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "6:perf_event:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "5:freezer:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "4:devices:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "3:blkio:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "2:memory:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.puts "1:name=systemd:/ecs/#{task_arn}/#{container_id}"
      cgroup_file.rewind
    end
  end
end
