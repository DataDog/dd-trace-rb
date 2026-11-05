require "spec_helper"
require "datadog/profiling"
require "datadog/profiling/remote"

RSpec.describe Datadog::Profiling::Remote do
  let(:remote) { described_class }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, client_configuration_change!: nil, report: nil) }
  let(:profiler) { instance_double(Datadog::Profiling::Profiler, start_failure: nil) }
  let(:profiler_build_error) { nil }
  let(:components) do
    instance_double(
      Datadog::Core::Configuration::Components,
      profiler: profiler,
      profiler_build_error: profiler_build_error,
    )
  end
  let(:contents) { [] }
  let(:repository) { instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents) }
  let(:apply_state) { Datadog::Core::Remote::Configuration::Content::ApplyState }

  let(:service_env_target) { [{"service" => "web", "env" => "prod"}] }
  let(:default_preset) do
    {
      "cpuTime" => true,
      "wallTime" => true,
      "heapObjects" => true,
      "heapSize" => true,
      "allocations" => true,
      "locks" => false,
      "exceptions" => false,
    }
  end
  let(:disabled_preset) { default_preset.transform_values { false } }

  def content(config_id, payload, product: "DEBUG")
    Datadog::Core::Remote::Configuration::Content.parse(
      {
        path: "datadog/2/#{product}/#{config_id}/config",
        content: payload.is_a?(String) ? payload : JSON.dump(payload),
      },
    )
  end

  def profiling_content(config_id, profilers: nil, settings: nil, targets: service_env_target, product: "DEBUG")
    payload = {"targets" => targets}
    payload["profilers"] = profilers if profilers
    payload["settings"] = settings if settings
    content(config_id, payload, product: product)
  end

  subject(:apply_configs) { remote.apply_configs(repository, telemetry) }

  before do
    settings.service = "web"
    settings.env = "prod"
    allow(Datadog).to receive(:configuration).and_return(settings)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components, allow_initialization: false).and_return(components)
    allow(Datadog::Profiling).to receive(:unsupported_reason).and_return(nil)
    allow(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)
  end

  describe ".products" do
    it "subscribes to the APM_PROFILING and DEBUG products" do
      expect(remote.products).to eq(["APM_PROFILING", "DEBUG"])
    end
  end

  describe ".receivers" do
    let(:receivers) { remote.receivers(telemetry) }

    def matches?(product)
      path = Datadog::Core::Remote::Configuration::Path.parse("datadog/2/#{product}/id/config")
      receivers.any? { |receiver| receiver.match?(path) }
    end

    it "matches only APM_PROFILING and DEBUG content" do
      expect(matches?("APM_PROFILING")).to be true
      expect(matches?("DEBUG")).to be true
      expect(matches?("APM_TRACING")).to be false
    end

    it "applies the repository when called" do
      contents << profiling_content("preset-default", profilers: default_preset)

      expect { receivers.first.call(repository, []) }.to change { settings.profiling.enabled }.from(false).to(true)
    end

    it "reports changes to the telemetry it was given" do
      contents << profiling_content("preset-default", profilers: default_preset)

      expect(telemetry).to receive(:client_configuration_change!)

      receivers.first.call(repository, [])
    end

    context "when a new client's first sync finds that the config enabling profiling was removed" do
      let(:dispatcher) { Datadog::Core::Remote::Dispatcher.new(receivers) }

      before do
        contents << profiling_content("preset-default", profilers: default_preset)
        remote.apply_configs(repository, telemetry)
        contents.clear
      end

      it "restores the local values" do
        expect(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)

        expect { dispatcher.reconcile([], repository) }.to change { settings.profiling.enabled }.from(true).to(false)
      end
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
        expect(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)

        apply_configs
      end

      it "reports the remote values to telemetry" do
        expect(telemetry).to receive(:client_configuration_change!).with(
          contain_exactly(
            ["DD_PROFILING_ENABLED", true],
            ["DD_PROFILING_ALLOCATION_ENABLED", true],
            ["DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED", true],
            ["DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED", true],
            ["DD_PROFILING_MAX_FRAMES", nil],
            ["DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED", nil],
          ),
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
        expect(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)

        expect { apply_configs }.to change { settings.profiling.enabled }.from(true).to(false)
      end
    end

    context "when heapSize is requested and heap size profiling is disabled locally" do
      let(:contents) { [profiling_content("id", profilers: {"heapSize" => true})] }

      before do
        settings.profiling.enabled = true
        settings.profiling.allocation_enabled = true
        settings.profiling.advanced.experimental_heap_enabled = true
        settings.profiling.advanced.experimental_heap_size_enabled = false
      end

      it "enables heap size profiling, restarting the profiler for it alone" do
        expect(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)
        expect(telemetry).to receive(:client_configuration_change!)
          .with(include(["DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED", true]))

        expect { apply_configs }
          .to change { settings.profiling.advanced.experimental_heap_size_enabled }.from(false).to(true)
      end
    end

    describe "heap and allocation profiling" do
      # Expected [enabled, allocation, heap objects, heap size], from local allocation and heap settings. Heap
      # size is whether heap size profiling ends up enabled, which also needs heap objects.
      [
        ["allocations alone", {"allocations" => true}, [false, false], [true, true, false, false]],
        ["heapObjects alone", {"heapObjects" => true}, [false, false], [true, true, true, true]],
        ["heapSize alone, with the heap objects it needs", {"heapSize" => true}, [false, false], [true, true, true, true]],
        ["heapSize, even with allocations disabled", {"heapSize" => true, "allocations" => false}, [false, false], [true, true, true, true]],
        ["heapSize, even with heapObjects disabled", {"heapObjects" => false, "heapSize" => true}, [false, false], [true, true, true, true]],
        ["heapObjects without heapSize", {"heapObjects" => true, "heapSize" => false}, [false, false], [true, true, true, false]],
        ["both disabled, keeping local allocations", {"heapObjects" => false, "heapSize" => false}, [true, true], [false, true, false, false]],
        ["heapSize disabled, keeping local heap objects", {"heapSize" => false}, [true, true], [false, true, true, false]],
        ["heapSize disabled, keeping local allocations", {"cpuTime" => true, "heapSize" => false}, [true, false], [true, true, false, false]],
      ].each do |description, profilers, (local_allocation, local_heap), expected|
        it "handles #{description}" do
          settings.profiling.allocation_enabled = local_allocation
          settings.profiling.advanced.experimental_heap_enabled = local_heap
          contents << profiling_content("id", profilers: profilers)

          apply_configs

          profiling = settings.profiling
          heap = profiling.advanced.experimental_heap_enabled
          heap_size = heap && profiling.advanced.experimental_heap_size_enabled
          expect([profiling.enabled, profiling.allocation_enabled, heap, heap_size]).to eq(expected)
        end
      end
    end

    context "when only cpuTime is requested" do
      let(:contents) { [profiling_content("id", profilers: {"cpuTime" => true})] }

      it "enables profiling" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when cpuTime and wallTime are turned off and the other profilers omitted" do
      let(:cpu_and_wall_off) { profiling_content("off", profilers: {"cpuTime" => false, "wallTime" => false}) }
      let(:contents) { [cpu_and_wall_off] }

      before { settings.profiling.enabled = true }

      it "disables profiling, as no other profiler runs locally" do
        apply_configs

        expect(settings.profiling.enabled).to be false
      end

      context "with allocation profiling enabled locally" do
        before { settings.profiling.allocation_enabled = true }

        it "keeps profiling enabled, as allocation profiling still runs" do
          apply_configs

          expect(settings.profiling.enabled).to be true
        end
      end

      context "after a config enabled allocation profiling remotely" do
        before do
          contents.replace([profiling_content("allocations", profilers: {"allocations" => true})])
          remote.apply_configs(repository, telemetry)
          contents.replace([cpu_and_wall_off])
        end

        it "disables profiling, as only the local settings count" do
          apply_configs

          expect(settings.profiling.enabled).to be false
        end
      end
    end

    context "when only profilers without a Ruby equivalent are requested" do
      let(:contents) { [profiling_content("id", profilers: {"locks" => true, "exceptions" => true})] }

      it "changes nothing" do
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

    [:auto, true].each do |local_value|
      context "with rubySignalWorkaround: false and a local #{local_value.inspect} value" do
        let(:contents) do
          [profiling_content("id", profilers: default_preset, settings: {"rubySignalWorkaround" => false})]
        end

        before { settings.profiling.advanced.no_signals_workaround_enabled = local_value }

        it "keeps the local value, which can detect gems that are incompatible with signals" do
          expect { apply_configs }.to_not(change { settings.profiling.advanced.no_signals_workaround_enabled })
        end
      end
    end

    describe "maxStackDepth" do
      def apply_max_stack_depth(depth)
        contents << profiling_content("id", profilers: default_preset, settings: {"maxStackDepth" => depth})
        apply_configs
      end

      [4, 3001].each do |depth|
        it "accepts #{depth}, leaving it to the profiler to clamp it" do
          apply_max_stack_depth(depth)

          expect(settings.profiling.advanced.max_frames).to eq(depth)
          expect(contents.first.apply_state).to eq(apply_state::ACKNOWLEDGED)
        end
      end

      ["500", 500.0].each do |depth|
        it "rejects #{depth.inspect}, which is not an integer, and keeps the local value" do
          apply_max_stack_depth(depth)

          expect(settings.profiling.advanced.max_frames).to eq(400)
          expect(contents.first.apply_error).to eq("settings.maxStackDepth has an invalid value")
        end
      end
    end

    context "with settings meant for other languages" do
      let(:contents) do
        [profiling_content("id", profilers: {}, settings: {"pythonMemoryMemDomain" => true})]
      end

      it "ignores them without reporting an error" do
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

      it "normalizes the service and env like the agent, as the targets are normalized" do
        settings.service = "Web App"
        settings.env = "Prod"

        expect(enabled_for([{"service" => "web_app", "env" => "prod"}])).to be true
      end

      it "normalizes the targets too" do
        expect(enabled_for([{"service" => "Web", "env" => "PROD"}])).to be true
      end

      it "treats an empty env as no env" do
        settings.env = ""

        expect(enabled_for([{"env" => "staging"}])).to be true
      end

      it "leaves matching tags to the backend, which sees tags the tracer can't" do
        expect(enabled_for([{"service" => "web", "tags" => ["host_tag:value"]}])).to be true
      end
    end

    describe "debug logs" do
      let(:log) { StringIO.new }

      before do
        allow(Datadog).to receive(:logger).and_return(Datadog::Core::Logger.new(log).tap { |l| l.level = ::Logger::DEBUG })
      end

      it "logs the scope of each matching config, and the targets of each dropped one" do
        contents << profiling_content("env-config", profilers: default_preset, targets: [{"env" => "prod"}])
        contents << profiling_content("other-config", profilers: default_preset, targets: [{"service" => "other"}])

        apply_configs

        expect(log.string).to include("Profiling RC: config env-config scope=env specificity=2")
        targets = [{service: "other", env: nil, tags: []}]
        expect(log.string).to include(
          "Profiling RC: dropped config other-config (targets=#{targets.inspect}, self=web/prod)",
        )
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
          "a", profilers: disabled_preset, targets: [{"service" => "web", "env" => "staging"}, {"env" => "prod"}],
        )
        contents << profiling_content("b", profilers: default_preset, targets: [{"service" => "web"}])

        apply_configs

        expect(settings.profiling.enabled).to be true
      end

      it "merges fields from less specific configs" do
        contents << profiling_content("env", profilers: default_preset, targets: [{"env" => "prod"}])
        contents << profiling_content(
          "svc", profilers: {}, settings: {"maxStackDepth" => 100}, targets: [{"service" => "web"}],
        )

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
        remote.apply_configs(repository, telemetry)
        contents.clear
      end

      it "restores the local values and restarts the profiler" do
        expect(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler)

        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when the repository is dispatched again without profiling changes" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      before { remote.apply_configs(repository, telemetry) }

      it "doesn't report the unchanged values to telemetry again" do
        expect(telemetry).to_not receive(:client_configuration_change!)

        contents << content("other-team", {"something" => "else"})
        apply_configs
      end

      it "doesn't reconfigure the profiler again" do
        expect(Datadog::Core::Configuration::Components).to_not receive(:reconfigure_profiler)

        contents << content("other-team", {"something" => "else"})
        apply_configs
      end
    end

    context "when the remote value equals the local one" do
      let(:contents) { [profiling_content("cpu", profilers: {"cpuTime" => true})] }

      before { settings.profiling.enabled = true }

      it "still reports it to telemetry" do
        expect(telemetry).to receive(:client_configuration_change!)
          .with(include(["DD_PROFILING_ENABLED", true]))

        apply_configs
      end

      it "reports its removal to telemetry" do
        remote.apply_configs(repository, telemetry)
        contents.clear

        expect(telemetry).to receive(:client_configuration_change!)
          .with(include(["DD_PROFILING_ENABLED", nil]))

        apply_configs
      end
    end

    context "with content from other DEBUG users" do
      let(:contents) do
        [
          content("json", {"something" => "else"}),
          content("text", "not json"),
          # A generic settings section, even with a key profiling also uses, doesn't make it profiling content.
          content("settings", {"settings" => {"maxStackDepth" => 100, "verbose" => true}}),
        ]
      end

      it "leaves it unacknowledged" do
        apply_configs

        expect(contents.map(&:apply_state)).to all(eq(apply_state::UNACKNOWLEDGED))
      end
    end

    context "with content of the APM_PROFILING product" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset, product: "APM_PROFILING")] }

      it "applies it" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)

        expect(contents.first.apply_state).to eq(apply_state::ACKNOWLEDGED)
      end
    end

    context "with malformed content of the APM_PROFILING product" do
      let(:contents) do
        [
          content("text", "not json", product: "APM_PROFILING"),
          content("array", [1], product: "APM_PROFILING"),
          content("no-profilers", {"targets" => []}, product: "APM_PROFILING"),
        ]
      end

      it "reports it as errored" do
        apply_configs

        expect(contents.map(&:apply_state)).to all(eq(apply_state::ERROR))
        expect(contents.map(&:apply_error)).to all(eq("not a JSON object with profilers"))
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
            settings: {"maxStackDepth" => "deep", "rubySignalWorkaround" => true},
          ),
        ]
      end

      it "reports the invalid fields as an error" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ERROR)
        expect(contents.first.apply_error).to eq(
          "profilers.cpuTime has an invalid value; settings.maxStackDepth has an invalid value",
        )
      end

      it "still applies the valid fields" do
        expect { apply_configs }
          .to change { settings.profiling.allocation_enabled }.from(false).to(true)
          .and change { settings.profiling.advanced.no_signals_workaround_enabled }.from(:auto).to(true)

        expect(settings.profiling.advanced.max_frames).to eq(400)
      end
    end

    describe "invalid payloads" do
      enabling = {"cpuTime" => true}
      [
        [
          "sections that are not objects",
          {"profilers" => [], "settings" => "x", "targets" => []},
          "profilers is not an object; settings is not an object", false,
        ],
        [
          "a null profilers section",
          {"profilers" => nil, "targets" => []},
          "profilers is not an object", false,
        ],
        [
          "only invalid targets, dropping the config rather than matching every tracer",
          {"profilers" => enabling, "targets" => [{"service" => 1}, "web"]},
          "targets[0] is invalid; targets[1] is invalid; no valid targets", false,
        ],
        [
          "some invalid targets, applying the config with the valid ones",
          {"profilers" => enabling, "targets" => [{"env" => ["prod"]}, {"service" => "web"}]},
          "targets[0] is invalid", true,
        ],
        [
          "targets that are not an array, dropping the config",
          {"profilers" => enabling, "targets" => {"service" => "web"}},
          "targets is not an array", false,
        ],
      ].each do |description, payload, error, enabled|
        it "reports #{description}" do
          contents << content("id", payload)

          apply_configs

          expect(contents.first.apply_error).to eq(error)
          expect(settings.profiling.enabled).to be(enabled)
        end
      end
    end

    context "when components are not built yet" do
      let(:components) { nil }
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      it "applies the settings without raising" do
        expect { apply_configs }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end

    context "when profiling is requested but not supported" do
      let(:contents) do
        [
          profiling_content("preset-default", profilers: default_preset),
          profiling_content("no-enablement", profilers: {}),
        ]
      end

      let(:profiler) { nil }

      before { allow(Datadog::Profiling).to receive(:unsupported_reason).and_return("test reason") }

      it "reports every config as errored with the reason, including one that doesn't enable profiling" do
        apply_configs

        expect(contents.map(&:apply_state)).to all(eq(apply_state::ERROR))
        expect(contents.map(&:apply_error)).to all(eq("Profiling is not supported: test reason"))
      end
    end

    context "when profiling is enabled locally but not supported" do
      let(:contents) { [profiling_content("no-enablement", profilers: {})] }
      let(:profiler) { nil }

      before do
        settings.profiling.enabled = true
        allow(Datadog::Profiling).to receive(:unsupported_reason).and_return("test reason")
      end

      it "reports a config that doesn't enable profiling as errored too" do
        apply_configs

        expect(contents.first.apply_error).to eq("Profiling is not supported: test reason")
      end
    end

    context "without profiling content" do
      before { settings.profiling.enabled = true }

      it "doesn't wait for the profiler to start, as there is nothing to acknowledge" do
        expect(profiler).to_not receive(:start_failure)

        apply_configs
      end
    end

    context "when the profiler fails to start" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      it "reports the config as errored with the failure, instead of applied" do
        expect(profiler).to receive(:start_failure).with(timeout_seconds: described_class::START_TIMEOUT_SECONDS)
          .and_return(Datadog::Profiling::ExistingSignalHandler.new("test failure"))

        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ERROR)
        expect(contents.first.apply_error)
          .to eq("Profiling failed to start: Datadog::Profiling::ExistingSignalHandler: test failure")
      end
    end

    context "when the profiler fails to initialize" do
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }
      let(:profiler) { nil }
      let(:profiler_build_error) { ArgumentError.new("test error") }

      it "reports the config as errored with the error, instead of applied" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ERROR)
        expect(contents.first.apply_error).to eq("Profiling failed to initialize: ArgumentError: test error")
      end

      context "without an error recorded" do
        let(:profiler_build_error) { nil }

        it "reports the config as errored" do
          apply_configs

          expect(contents.first.apply_error).to eq("Profiling failed to initialize")
        end
      end
    end

    context "when profiling is disabled remotely and not supported" do
      let(:contents) { [profiling_content("preset-disabled", profilers: disabled_preset)] }
      let(:profiler) { nil }

      before { allow(Datadog::Profiling).to receive(:unsupported_reason).and_return("test reason") }

      it "acknowledges the config, which is honored" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ACKNOWLEDGED)
      end
    end

    context "when applying fails" do
      let(:error) { RuntimeError.new("test failure") }
      let(:contents) { [profiling_content("preset-default", profilers: default_preset)] }

      before { allow(Datadog::Core::Configuration::Components).to receive(:reconfigure_profiler).and_raise(error) }

      it "reports the error to telemetry instead of raising" do
        expect(telemetry).to receive(:report).with(error, description: "Failed to apply profiling remote configs")

        expect { apply_configs }.to_not raise_error
      end

      it "reports the config as errored instead of applied" do
        apply_configs

        expect(contents.first.apply_state).to eq(apply_state::ERROR)
        expect(contents.first.apply_error).to start_with("RuntimeError: test failure")
      end

      context "with content from other DEBUG users" do
        let(:contents) { [profiling_content("preset-default", profilers: default_preset), content("other", {"x" => 1})] }

        it "leaves it unacknowledged" do
          apply_configs

          expect(contents.last.apply_state).to eq(apply_state::UNACKNOWLEDGED)
        end
      end
    end
  end
end
