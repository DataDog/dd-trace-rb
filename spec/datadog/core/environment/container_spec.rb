require "spec_helper"
require "support/container_helpers"
require "datadog/core/environment/container"

RSpec.describe Datadog::Core::Environment::Container do
  around do |example|
    described_class.remove_instance_variable(:@entry) if described_class.instance_variable_defined?(:@entry)
    example.run
    described_class.remove_instance_variable(:@entry) if described_class.instance_variable_defined?(:@entry)
  end

  describe "::entry" do
    subject(:entry) { described_class.entry }

    shared_examples_for "container entry" do
      before { expect(Datadog.logger).to_not receive(:error) }

      it do
        is_expected.to be_a_kind_of(described_class::Entry)
        is_expected.to have_attributes(
          platform: platform,
          container_id: container_id,
          task_uid: task_uid,
        )
      end
    end

    context "when in a non-containerized environment" do
      include_context "non-containerized environment"

      it_behaves_like "container entry" do
        let(:container_id) { nil }
        let(:task_uid) { nil }
      end
    end

    context "when in a non-containerized environment with VTE" do
      include_context "non-containerized environment with VTE"

      it_behaves_like "container entry" do
        let(:container_id) { terminal_id }
        let(:task_uid) { nil }
      end
    end

    context "when in a Docker environment" do
      include_context "Docker environment"

      it_behaves_like "container entry" do
        let(:task_uid) { nil }
      end
    end

    context "when in a Docker systemd environment" do
      include_context "Docker systemd environment"

      it_behaves_like "container entry" do
        let(:task_uid) { nil }
      end
    end

    context "when in a Kubernetes burstable environment" do
      include_context "Kubernetes burstable environment"

      it_behaves_like "container entry" do
        let(:task_uid) { pod_id }
      end
    end

    context "when in a Kubernetes environment" do
      include_context "Kubernetes environment"

      it_behaves_like "container entry" do
        let(:task_uid) { pod_id }
      end
    end

    context "when in a ECS environment" do
      include_context "ECS environment"

      it_behaves_like "container entry" do
        let(:task_uid) { task_arn }
      end
    end

    context "when in a Fargate 1.3- environment" do
      include_context "Fargate 1.3- environment"

      it_behaves_like "container entry" do
        let(:task_uid) { task_arn }
      end
    end

    context "when in a Fargate 1.4+ environment" do
      include_context "Fargate 1.4+ environment"

      it_behaves_like "container entry" do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context "when in a Fargate 1.4+ (2-part) environment" do
      include_context "Fargate 1.4+ (2-part) environment"

      it_behaves_like "container entry" do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context "when in a Fargate 1.4+ (2-part short random) environment" do
      include_context "Fargate 1.4+ (2-part short random) environment"

      it_behaves_like "container entry" do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context "when in a Fargate 1.4+ with ECS+docker environment" do
      include_context "Fargate 1.4+ with ECS+docker environment"

      it_behaves_like "container entry" do
        let(:container_id) { child_container_id }
        let(:task_uid) { task_arn }
      end
    end

    # Cgroups v2 tests
    context "when in a non-containerized v2 environment" do
      include_context "non-containerized v2 environment"

      it_behaves_like "container entry" do
        let(:container_id) { nil }
        let(:task_uid) { nil }
      end
    end

    context "when in a Docker v2 environment" do
      include_context "Docker v2 environment"

      it_behaves_like "container entry" do
        let(:task_uid) { nil }
      end
    end

    context "when in a Docker systemd v2 environment" do
      include_context "Docker systemd v2 environment"

      it_behaves_like "container entry" do
        let(:task_uid) { nil }
      end
    end

    context "when in a Kubernetes v2 environment" do
      include_context "Kubernetes v2 environment"

      it_behaves_like "container entry" do
        let(:task_uid) { pod_id }
      end
    end

    context "when in a Kubernetes burstable v2 environment" do
      include_context "Kubernetes burstable v2 environment"

      it_behaves_like "container entry" do
        let(:task_uid) { pod_id }
      end
    end

    context "when in an ECS v2 environment" do
      include_context "ECS v2 environment"

      it_behaves_like "container entry" do
        let(:task_uid) { task_arn }
      end
    end

    context "when in a Fargate 1.4+ v2 environment" do
      include_context "Fargate 1.4+ v2 environment"

      it_behaves_like "container entry" do
        let(:container_id) { container_id_with_random }
        let(:task_uid) { nil }
      end
    end

    context "when in a Docker hybrid v1/v2 environment on the host" do
      include_context "Docker hybrid v1/v2 environment"

      before { allow(described_class).to receive(:running_on_host?).and_return(true) }

      it_behaves_like "container entry" do
        let(:task_uid) { nil }
      end
    end

    context "when a Docker hybrid v1/v2 environment has a readable v2 inode" do
      include_context "Docker hybrid v1/v2 environment"

      let(:inode_path) { "/sys/fs/cgroup#{v2_path}" }

      before do
        allow(described_class).to receive(:running_on_host?).and_return(false)
        allow(File).to receive(:exist?).with(inode_path).and_return(true)
        allow(File).to receive(:exist?).with("/sys/fs/cgroup/cpuset/docker/#{container_id}").and_return(false)
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(inode_path).and_return(double(ino: 12345))
      end

      it "uses the v1 container ID for origin headers" do
        is_expected.to have_attributes(
          platform: platform,
          task_uid: nil,
          container_id: container_id,
          inode: nil,
        )
        expect(described_class.to_headers).to include(
          "Datadog-Container-ID" => container_id,
          "Datadog-Entity-ID" => "ci-#{container_id}",
        )
      end

      context "when the v2 path is not the root and has no container ID" do
        let(:v2_path) { "/user.slice/user-1000.slice" }

        it "uses the v1 container ID for origin headers" do
          is_expected.to have_attributes(
            platform: platform,
            task_uid: nil,
            container_id: container_id,
            inode: nil,
          )
          expect(described_class.to_headers).to include(
            "Datadog-Container-ID" => container_id,
            "Datadog-Entity-ID" => "ci-#{container_id}",
          )
        end
      end
    end

    context "when in a cgroup v2 private namespace environment" do
      include_context "cgroup v2 private namespace environment"

      let(:running_on_host) { false }
      let(:root_exists) { true }

      before do
        allow(described_class).to receive(:running_on_host?).and_return(running_on_host)
        allow(File).to receive(:exist?).with("/sys/fs/cgroup/").and_return(root_exists)
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with("/sys/fs/cgroup/").and_return(double(ino: 12345))
      end

      it "uses the root inode for origin headers" do
        is_expected.to have_attributes(platform: nil, task_uid: nil, container_id: nil, inode: 12345)
        expect(described_class.to_headers).to include("Datadog-Entity-ID" => "in-12345")
        expect(described_class.to_headers).not_to have_key("Datadog-Container-ID")
      end

      context "when running on the host" do
        let(:running_on_host) { true }

        it "omits the container identity" do
          is_expected.to eq(described_class::Entry.new)
          expect(described_class.to_headers).not_to include("Datadog-Container-ID", "Datadog-Entity-ID")
        end
      end

      context "when the cgroup filesystem root is absent" do
        let(:root_exists) { false }

        it "omits the container identity" do
          is_expected.to eq(described_class::Entry.new)
          expect(described_class.to_headers).not_to include("Datadog-Container-ID", "Datadog-Entity-ID")
        end
      end
    end

    context "when v1 entries precede v2 entries" do
      include_context "cgroup file"

      let(:v1_path) { "/docker/#{"a" * 64}" }
      let(:v2_path) { "/docker/#{"b" * 64}" }

      before do
        cgroup_file.puts "1:cpuset:#{v1_path}"
        cgroup_file.puts "0::#{v2_path}"
        cgroup_file.rewind

        allow(described_class).to receive(:running_on_host?).and_return(false)
        allow(File).to receive(:exist?).with("/sys/fs/cgroup/cpuset#{v1_path}").and_return(true)
        allow(File).to receive(:exist?).with("/sys/fs/cgroup#{v2_path}").and_return(true)
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with("/sys/fs/cgroup/cpuset#{v1_path}").and_return(double(ino: 11111))
        allow(File).to receive(:stat).with("/sys/fs/cgroup#{v2_path}").and_return(double(ino: 22222))
      end

      it "prefers the v2 container ID" do
        is_expected.to have_attributes(platform: "docker", task_uid: nil, container_id: "b" * 64, inode: nil)
        expect(described_class.to_headers).to include(
          "Datadog-Container-ID" => "b" * 64,
          "Datadog-Entity-ID" => "ci-#{"b" * 64}",
        )
      end

      context "when neither entry has a container ID" do
        let(:v1_path) { "/" }
        let(:v2_path) { "/user.slice/user-1000.slice" }

        it "keeps the v2 inode and platform as the fallback" do
          is_expected.to have_attributes(platform: "user", task_uid: nil, container_id: nil, inode: 22222)
          expect(described_class.to_headers).to include("Datadog-Entity-ID" => "in-22222")
          expect(described_class.to_headers).not_to have_key("Datadog-Container-ID")
        end
      end
    end

    context "when parsing cgroup entries raises an error" do
      before do
        allow(Datadog.logger).to receive(:debug)
        allow(Datadog::Core::Environment::Cgroup).to receive(:entries).and_raise(StandardError, "Test error")
      end

      it "logs the error and returns an empty entry" do
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

  describe "::entity_id" do
    subject(:entity_id) { described_class.entity_id }

    context "when container_id is present" do
      include_context "Docker environment"

      it "returns entity_id with ci- prefix" do
        expect(entity_id).to eq("ci-#{container_id}")
      end
    end

    context "when only inode is present (no container_id)" do
      before do
        allow(described_class).to receive(:container_id).and_return(nil)
        allow(described_class).to receive(:inode).and_return(12345)
      end

      it "returns entity_id with in- prefix" do
        expect(entity_id).to eq("in-12345")
      end
    end

    context "when neither container_id nor inode is present" do
      include_context "non-containerized environment"

      it "returns nil" do
        expect(entity_id).to be_nil
      end
    end
  end

  describe "::external_env" do
    subject(:external_env) { described_class.external_env }

    context "when configuration returns a string" do
      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return("provided-by-container-runner")
      end

      it "returns the configured value" do
        expect(external_env).to eq("provided-by-container-runner")
      end
    end

    context "when configuration returns nil" do
      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(nil)
      end

      it "returns nil" do
        expect(external_env).to be_nil
      end
    end
  end

  describe "::to_headers" do
    subject(:headers) { described_class.to_headers }

    context "when container headers and external_env are both present" do
      include_context "Docker environment"

      let(:external_env_value) { "provided-by-container-runner" }

      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(external_env_value)
      end

      it "includes all headers" do
        expect(headers).to include(
          "Datadog-Container-ID" => container_id,
          "Datadog-Entity-ID" => "ci-#{container_id}",
          "Datadog-External-Env" => external_env_value,
        )
      end
    end

    context "when container_id is nil and external_env is nil" do
      include_context "non-containerized environment"

      before do
        allow(Datadog.configuration.container).to receive(:external_env).and_return(nil)
      end

      it "returns empty hash (all nil values compacted)" do
        expect(headers).to eq({})
      end
    end
  end

  describe "::running_on_host?" do
    subject(:running_on_host) { described_class.running_on_host? }

    around do |example|
      described_class.remove_instance_variable(:@running_on_host) if described_class.instance_variable_defined?(:@running_on_host)
      example.run
      described_class.remove_instance_variable(:@running_on_host) if described_class.instance_variable_defined?(:@running_on_host)
    end

    context "when File.stat raises an error" do
      before do
        allow(Datadog.logger).to receive(:debug)
        allow(File).to receive(:exist?).with("/proc/self/ns/cgroup").and_return(true)
        allow(File).to receive(:stat).with("/proc/self/ns/cgroup").and_raise(StandardError, "Test error")
      end

      it "logs the error and returns false" do
        is_expected.to be(false)
        expect(Datadog.logger).to have_received(:debug) do |msg|
          expect(msg).to match(/Error while checking cgroup namespace/)
        end
      end
    end
  end
end
