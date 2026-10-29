require "spec_helper"
require "datadog/profiling/remote"

RSpec.describe Datadog::Profiling::Remote do
  let(:remote) { described_class }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, client_configuration_change!: nil, report: nil) }
  let(:components) do
    instance_double(Datadog::Core::Configuration::Components, telemetry: telemetry, reconfigure_profiler: nil)
  end
  let(:contents) { [] }
  let(:repository) { instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents) }
  let(:apply_state) { Datadog::Core::Remote::Configuration::Content::ApplyState }

  let(:service_env_target) { [{"service" => "web", "env" => "prod"}] }
  let(:default_preset) { {"cpuTime" => true, "wallTime" => true, "heapSize" => true, "allocations" => true, "lock" => false, "exception" => false} }
  let(:disabled_preset) { default_preset.transform_values { false } }

  def content(config_id, payload, product: "DEBUG")
    Datadog::Core::Remote::Configuration::Content.parse(
      {
        path: "datadog/2/#{product}/#{config_id}/config",
        content: payload.is_a?(String) ? payload : JSON.dump(payload),
      }
    )
  end

  def profiling_content(config_id, profilers: nil, settings: nil, targets: service_env_target)
    payload = {"targets" => targets}
    payload["profilers"] = profilers if profilers
    payload["settings"] = settings if settings
    content(config_id, payload)
  end

  subject(:apply_configs) { remote.apply_configs(repository) }

  before do
    settings.service = "web"
    settings.env = "prod"
    allow(Datadog).to receive(:configuration).and_return(settings)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components, allow_initialization: false).and_return(components)
  end

  describe ".products" do
    it "subscribes to the DEBUG product" do
      expect(remote.products).to eq(["DEBUG"])
    end
  end

  describe ".receivers" do
    let(:receivers) { remote.receivers(telemetry) }

    def matches?(product)
      path = Datadog::Core::Remote::Configuration::Path.parse("datadog/2/#{product}/id/config")
      receivers.any? { |receiver| receiver.match?(path) }
    end

    it "matches only DEBUG content" do
      expect(matches?("DEBUG")).to be true
      expect(matches?("APM_TRACING")).to be false
    end

    it "applies the repository when called" do
      contents << profiling_content("preset-default", profilers: default_preset)

      expect { receivers.first.call(repository, []) }.to change { settings.profiling.enabled }.from(false).to(true)
    end
  end

  describe ".apply_configs" do
    context "with the default preset targeting this service and env" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      it "enables profiling with allocation and heap profiling" do
        expect { apply_configs }
          .to change { settings.profiling.enabled }.from(false).to(true)
          .and change { settings.profiling.allocation_enabled }.from(false).to(true)
          .and change { settings.profiling.advanced.experimental_heap_enabled }.from(false).to(true)
      end

      it "sets the values at remote configuration precedence" do
        apply_configs

        expect(settings.profiling.options[:enabled].precedence_set)
          .to be Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
      end

      it "overrides an explicit local value" do
        settings.profiling.enabled = false

        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end

      it "restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        apply_configs
      end

      it "reports the remote values to telemetry" do
        expect(telemetry).to receive(:client_configuration_change!).with(
          contain_exactly(
            ["DD_PROFILING_ENABLED", true],
            ["DD_PROFILING_ALLOCATION_ENABLED", true],
            ["DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED", true],
            ["DD_PROFILING_MAX_FRAMES", nil],
            ["DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED", nil],
          )
        )

        apply_configs
      end

      it "acknowledges the content" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ACKNOWLEDGED)
      end
    end

    context "with the disabled preset" do
      let(:contents) { [profiling_content("preset-disabled", profilers: disabled_preset)] }

      before { settings.profiling.enabled = true }

      it "disables profiling and restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        expect { apply_configs }.to change { settings.profiling.enabled }.from(true).to(false)
      end
    end

    context "when only allocations is requested" do
      let(:contents) { [profiling_content("id", profilers: {"allocations" => true})] }

      it "enables profiling and keeps the local heap setting" do
        expect { apply_configs }
          .to change { settings.profiling.enabled }.from(false).to(true)
          .and change { settings.profiling.allocation_enabled }.from(false).to(true)

        expect(settings.profiling.advanced.experimental_heap_enabled).to be false
      end
    end

    context "when only heapSize is requested" do
      let(:contents) { [profiling_content("id", profilers: {"heapSize" => true})] }

      it "enables profiling with both heap and allocation profiling" do
        expect { apply_configs }
          .to change { settings.profiling.enabled }.from(false).to(true)
          .and change { settings.profiling.advanced.experimental_heap_enabled }.from(false).to(true)
          .and change { settings.profiling.allocation_enabled }.from(false).to(true)
      end
    end

    context "when heapSize is requested with allocations explicitly disabled" do
      let(:contents) { [profiling_content("id", profilers: {"heapSize" => true, "allocations" => false})] }

      it "still enables allocation profiling, which heap profiling needs" do
        expect { apply_configs }.to change { settings.profiling.allocation_enabled }.from(false).to(true)
      end
    end

    context "when heapSize is disabled and allocations omitted" do
      let(:contents) { [profiling_content("id", profilers: {"cpuTime" => true, "heapSize" => false})] }

      before { settings.profiling.allocation_enabled = true }

      it "keeps the local allocation setting" do
        apply_configs

        expect(settings.profiling.allocation_enabled).to be true
      end
    end

    context "when only cpuTime is requested" do
      let(:contents) { [profiling_content("id", profilers: {"cpuTime" => true})] }

      it "enables profiling" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when some mapped profilers are false and the others omitted" do
      let(:contents) { [profiling_content("id", profilers: {"cpuTime" => false, "wallTime" => false})] }

      before { settings.profiling.enabled = true }

      it "keeps the local enablement" do
        apply_configs

        expect(settings.profiling.enabled).to be true
      end
    end

    context "when only profilers without a Ruby equivalent are requested" do
      let(:contents) { [profiling_content("id", profilers: {"lock" => true, "exception" => true})] }

      it "changes nothing and does not restart the profiler" do
        expect(components).to_not receive(:reconfigure_profiler)

        expect { apply_configs }.to_not(change { settings.profiling.enabled })
      end
    end

    context "with settings" do
      let(:contents) do
        [
          profiling_content(
            "id",
            profilers: default_preset,
            settings: {"maxStackDepth" => 200, "rubySignalWorkaround" => true},
          ),
        ]
      end

      it "maps them to the profiler settings" do
        expect { apply_configs }
          .to change { settings.profiling.advanced.max_frames }.from(400).to(200)
          .and change { settings.profiling.advanced.no_signals_workaround_enabled }.from(:auto).to(true)
      end
    end

    context "with settings meant for other languages" do
      let(:contents) do
        [profiling_content("id", settings: {"pythonMemoryMemDomain" => true})]
      end

      it "ignores them without reporting an error" do
        expect(components).to_not receive(:reconfigure_profiler)

        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ACKNOWLEDGED)
      end
    end

    describe "targeting" do
      def enabled_for(targets)
        contents << profiling_content("id", profilers: default_preset, targets: targets)
        apply_configs
        settings.profiling.enabled
      end

      it "matches a config without targets" do
        expect(enabled_for(nil)).to be true
      end

      it "matches an empty target list" do
        expect(enabled_for([])).to be true
      end

      it "matches an omitted or wildcard service" do
        expect(enabled_for([{"env" => "prod"}, {"service" => "*", "env" => "prod"}])).to be true
      end

      it "does not match another service" do
        expect(enabled_for([{"service" => "other", "env" => "prod"}])).to be false
      end

      it "does not match another env" do
        expect(enabled_for([{"service" => "web", "env" => "staging"}])).to be false
      end

      it "matches when any target matches" do
        expect(enabled_for([{"service" => "other"}, {"service" => "web"}])).to be true
      end

      it "uses remote.service when set, as the RC client does" do
        settings.remote.service = "rc-web"

        expect(enabled_for([{"service" => "rc-web"}])).to be true
      end

      it "matches any env target when the tracer has no env, as it inherits the agent's env" do
        settings.env = nil

        expect(enabled_for([{"service" => "web", "env" => "staging"}])).to be true
      end

      it "treats an empty env as no env" do
        settings.env = ""

        expect(enabled_for([{"env" => "staging"}])).to be true
      end

      it "leaves matching tags to the backend, which sees tags the tracer can't" do
        expect(enabled_for([{"service" => "web", "tags" => ["host_tag:value"]}])).to be true
      end
    end

    describe "merging" do
      [
        [[{"service" => "web", "env" => "prod"}], [{"service" => "web"}]],
        [[{"service" => "web"}], [{"env" => "prod"}]],
        [[{"env" => "prod"}], [{"tags" => ["team:profiling"]}]],
        [[{"tags" => ["team:profiling"]}], []],
      ].each do |more_specific, less_specific|
        it "prefers #{more_specific.inspect} over #{less_specific.inspect}, regardless of config id" do
          contents << profiling_content("a", profilers: disabled_preset, targets: less_specific)
          contents << profiling_content("b", profilers: default_preset, targets: more_specific)
          contents << profiling_content("c", profilers: disabled_preset, targets: less_specific)

          apply_configs

          expect(settings.profiling.enabled).to be true
        end
      end

      it "ranks a config by its most specific matching target, ignoring targets that do not match" do
        contents << profiling_content(
          "a", profilers: disabled_preset, targets: [{"service" => "web", "env" => "staging"}, {"env" => "prod"}]
        )
        contents << profiling_content("b", profilers: default_preset, targets: [{"service" => "web"}])

        apply_configs

        expect(settings.profiling.enabled).to be true
      end

      it "merges fields from less specific configs" do
        contents << profiling_content("env", profilers: default_preset, targets: [{"env" => "prod"}])
        contents << profiling_content("svc", settings: {"maxStackDepth" => 100}, targets: [{"service" => "web"}])

        apply_configs

        expect(settings.profiling.enabled).to be true
        expect(settings.profiling.advanced.max_frames).to eq(100)
      end

      it "breaks specificity ties by config id, independently of delivery order" do
        contents << profiling_content("b", profilers: disabled_preset)
        contents << profiling_content("a", profilers: default_preset)

        apply_configs

        expect(settings.profiling.enabled).to be false
      end
    end

    context "when a previously applied config is removed" do
      before do
        settings.profiling.enabled = true
        contents << profiling_content("preset-disabled", profilers: disabled_preset)
        remote.apply_configs(repository)
        contents.clear
      end

      it "restores the local values and restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when the repository is dispatched again without profiling changes" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      before { remote.apply_configs(repository) }

      it "neither restarts the profiler nor reports telemetry" do
        expect(components).to_not receive(:reconfigure_profiler)
        expect(telemetry).to_not receive(:client_configuration_change!)

        contents << content("other-team", {"something" => "else"})
        apply_configs
      end
    end

    context "with content from other DEBUG users" do
      let(:contents) { [content("json", {"something" => "else"}), content("text", "not json")] }

      it "leaves it unacknowledged" do
        apply_configs

        expect(contents.map(&:apply_state)).to all(eq(apply_state::UNACKNOWLEDGED))
      end

      it "does not restart the profiler" do
        expect(components).to_not receive(:reconfigure_profiler)

        apply_configs
      end
    end

    context "with content of another product in the repository" do
      let(:contents) { [content("id", {"profilers" => default_preset}, product: "APM_TRACING")] }

      it "ignores it" do
        expect { apply_configs }.to_not(change { settings.profiling.enabled })
      end
    end

    context "with invalid fields" do
      let(:contents) do
        [
          profiling_content(
            "id",
            profilers: {"cpuTime" => "yes", "allocations" => true},
            settings: {"maxStackDepth" => 0, "rubySignalWorkaround" => true},
          ),
        ]
      end

      it "reports the invalid fields as an error" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ERROR)
        expect(contents.first.apply_error).to eq(
          "profilers.cpuTime has an invalid value; settings.maxStackDepth has an invalid value"
        )
      end

      it "still applies the valid fields" do
        expect { apply_configs }
          .to change { settings.profiling.allocation_enabled }.from(false).to(true)
          .and change { settings.profiling.advanced.no_signals_workaround_enabled }.from(:auto).to(true)

        expect(settings.profiling.advanced.max_frames).to eq(400)
      end
    end

    context "with sections that are not objects" do
      let(:contents) { [content("id", {"profilers" => [], "settings" => "x", "targets" => []})] }

      it "reports them as an error" do
        apply_configs

        expect(contents.first.apply_error).to eq("profilers is not an object; settings is not an object")
      end
    end

    context "when every target is invalid" do
      let(:contents) do
        [profiling_content("id", profilers: default_preset, targets: [{"service" => 1}, "web"])]
      end

      it "drops the config instead of matching every tracer" do
        expect { apply_configs }.to_not(change { settings.profiling.enabled })

        expect(contents.first.apply_error).to eq("targets[0] is invalid; targets[1] is invalid; no valid targets")
      end
    end

    context "when some targets are invalid" do
      let(:contents) do
        [profiling_content("id", profilers: default_preset, targets: [{"env" => ["prod"]}, {"service" => "web"}])]
      end

      it "applies the config using the valid targets and reports the invalid ones" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)

        expect(contents.first.apply_error).to eq("targets[0] is invalid")
      end
    end

    context "when targets is not an array" do
      let(:contents) { [profiling_content("id", profilers: default_preset, targets: {"service" => "web"})] }

      it "drops the config" do
        expect { apply_configs }.to_not(change { settings.profiling.enabled })

        expect(contents.first.apply_error).to eq("targets is not an array")
      end
    end

    context "when components are not built yet" do
      let(:components) { nil }
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      it "applies the settings without raising" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when applying fails" do
      let(:error) { RuntimeError.new("test failure") }
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      before { allow(components).to receive(:reconfigure_profiler).and_raise(error) }

      it "reports the error to telemetry instead of raising" do
        expect(telemetry).to receive(:report).with(error, description: "Failed to apply profiling remote configs")

        expect { apply_configs }.to_not raise_error
      end
    end
  end
end
