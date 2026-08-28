require "spec_helper"

RSpec.describe Datadog::Tracing::Remote do
  let(:remote) { described_class }
  let(:path) { "datadog/1/APM_TRACING/anything/lib_config" }

  it "declares the APM_TRACING product" do
    expect(remote.products).to contain_exactly("APM_TRACING")
  end

  it "declares tracing capabilities (DI enablement bit 38 lives in DI::Remote)" do
    expect(remote.capabilities).to contain_exactly(1 << 12, 1 << 13, 1 << 14, 1 << 29, 1 << 45)
  end

  it "declares matches that match APM_TRACING" do
    telemetry = instance_double(Datadog::Core::Telemetry::Component)

    expect(remote.receivers(telemetry)).to all(
      match(
        lambda do |receiver|
          receiver.match? Datadog::Core::Remote::Configuration::Path.parse(path)
        end
      )
    )
  end

  describe "#merge_and_apply_configs with a single config" do
    subject(:apply_configs) { remote.merge_and_apply_configs(repository) }
    let(:config) { {"lib_config" => {}} }
    let(:content) do
      Datadog::Core::Remote::Configuration::Content.parse({path: path, content: JSON.dump(config)})
    end
    let(:repository) do
      instance_double(Datadog::Core::Remote::Configuration::Repository, contents: [content])
    end

    before do
      allow(Datadog.configuration).to receive(:service).and_return("web")
      allow(Datadog.configuration).to receive(:env).and_return("prod")
      allow(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
    end

    context "with an unparseable content" do
      let(:content) { Datadog::Core::Remote::Configuration::Content.parse({path: path, content: ""}) }

      it "sets errored apply state and reports the parse failure to telemetry" do
        expect(Datadog.send(:components).telemetry).to receive(:report)
          .with(kind_of(StandardError), description: "Failed to parse APM_TRACING remote config")
        apply_configs
        expect(content.apply_state).to eq(3)
        expect(content.apply_error).to include("JSON")
      end
    end

    context "with a valid content" do
      context "and nothing configured" do
        let(:config) { {"lib_config" => {}} }

        it "sets ok applied state and sends telemetry with empty values" do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ["DD_LOGS_INJECTION", nil],
              ["DD_TRACE_HEADER_TAGS", nil],
              ["DD_TRACE_SAMPLE_RATE", nil],
              ["DD_TRACE_SAMPLING_RULES", nil],
            ))

          apply_configs

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end

      context "and one option configured" do
        let(:config) { {"lib_config" => {"log_injection_enabled" => false}} }

        it "sets ok applied state and sends telemetry with configuration value" do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ["DD_LOGS_INJECTION", false],
              ["DD_TRACE_HEADER_TAGS", nil],
              ["DD_TRACE_SAMPLE_RATE", nil],
              ["DD_TRACE_SAMPLING_RULES", nil],
            ))

          apply_configs

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end

      context "and tracing header tags configured" do
        let(:config) do
          {
            "lib_config" => {
              "tracing_header_tags" => [
                {"header" => "X-Test-Header", "tag_name" => "test_header_rc"},
                {"header" => "Content-Length", "tag_name" => ""},
              ],
            },
          }
        end

        it "sends the comma-separated applied value to telemetry" do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ["DD_LOGS_INJECTION", nil],
              ["DD_TRACE_HEADER_TAGS", "X-Test-Header:test_header_rc,Content-Length:"],
              ["DD_TRACE_SAMPLE_RATE", nil],
              ["DD_TRACE_SAMPLING_RULES", nil],
            ))

          apply_configs

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end

      context "and tracing sampling rules configured" do
        let(:config) do
          {
            "lib_config" => {
              "tracing_sampling_rules" => [
                {
                  "sample_rate" => 1.0,
                  "tags" => [{"key" => "service", "value_glob" => "web-*"}],
                },
              ],
            },
          }
        end

        it "sends the JSON applied value to telemetry" do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ["DD_LOGS_INJECTION", nil],
              ["DD_TRACE_HEADER_TAGS", nil],
              ["DD_TRACE_SAMPLE_RATE", nil],
              ["DD_TRACE_SAMPLING_RULES", "[{\"sample_rate\":1.0,\"tags\":{\"service\":\"web-*\"}}]"],
            ))

          apply_configs

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end

      context "and dynamic_instrumentation_enabled is configured" do
        let(:symbol_database) do
          instance_double(
            Datadog::SymbolDatabase::Component,
            resume_pending_upload: nil,
            stop_for_di_disable: nil,
          )
        end
        let(:remote_component) do
          instance_double(Datadog::Core::Remote::Component, add_products: nil, remove_products: nil)
        end
        # handle_rc_enablement (isolated here) is what actually starts DI; expose
        # a component whose started? state the individual contexts control.
        let(:di_component) { instance_double(Datadog::DI::Component, started?: true) }

        before do
          # Isolate the Symbol Database replay wiring from DI's own enablement.
          allow(Datadog::DI::Remote).to receive(:handle_rc_enablement)
          components = Datadog.send(:components)
          allow(components).to receive(:symbol_database).and_return(symbol_database)
          allow(components).to receive(:remote).and_return(remote_component)
          allow(components).to receive(:dynamic_instrumentation).and_return(di_component)
          allow(components.telemetry).to receive(:client_configuration_change!)
          allow(Datadog::SymbolDatabase::Remote).to receive(:deferred_products)
            .and_return(["LIVE_DEBUGGING_SYMBOL_DB"])
        end

        context "to true" do
          let(:config) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

          context "and the DI component started" do
            it "replays deferred Symbol Database upload and advertises the DI products" do
              expect(symbol_database).to receive(:resume_pending_upload)
              expect(symbol_database).not_to receive(:stop_for_di_disable)
              expect(remote_component).to receive(:add_products)
                .with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

              apply_configs

              expect(content.apply_state).to eq(2)
            end
          end

          context "but the DI component did not start (unsupported runtime or explicitly disabled)" do
            let(:di_component) { nil }

            it "withdraws the DI products instead of advertising them" do
              expect(remote_component).not_to receive(:add_products)
              expect(remote_component).to receive(:remove_products)
                .with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

              apply_configs

              expect(content.apply_state).to eq(2)
            end
          end
        end

        context "to false" do
          let(:config) { {"lib_config" => {"dynamic_instrumentation_enabled" => false}} }

          it "stops Symbol Database (follows-DI case), withdraws products, and does not replay" do
            expect(symbol_database).to receive(:stop_for_di_disable)
            expect(symbol_database).not_to receive(:resume_pending_upload)
            expect(remote_component).to receive(:remove_products)
              .with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

            apply_configs

            expect(content.apply_state).to eq(2)
          end
        end
      end
    end
  end

  describe "#config_matches?" do
    it "matches when service_target is absent" do
      expect(remote.config_matches?({"lib_config" => {}}, "web", "prod")).to be(true)
    end

    it "matches wildcard service and env" do
      config = {"service_target" => {"service" => "*", "env" => "*"}}
      expect(remote.config_matches?(config, "web", "prod")).to be(true)
    end

    it "matches a concrete service+env equal to ours" do
      config = {"service_target" => {"service" => "web", "env" => "prod"}}
      expect(remote.config_matches?(config, "web", "prod")).to be(true)
    end

    it "drops a config for a different concrete service" do
      config = {"service_target" => {"service" => "other", "env" => "*"}}
      expect(remote.config_matches?(config, "web", "prod")).to be(false)
    end

    it "drops a config for a different concrete env" do
      config = {"service_target" => {"service" => "*", "env" => "staging"}}
      expect(remote.config_matches?(config, "web", "prod")).to be(false)
    end
  end

  describe "#config_priority" do
    it "ranks service+env highest (5)" do
      expect(remote.config_priority({"service_target" => {"service" => "web", "env" => "prod"}})).to eq(5)
    end

    it "ranks service-only as 4" do
      expect(remote.config_priority({"service_target" => {"service" => "web", "env" => "*"}})).to eq(4)
    end

    it "ranks env-only as 3" do
      expect(remote.config_priority({"service_target" => {"service" => "*", "env" => "prod"}})).to eq(3)
    end

    it "ranks cluster as 2" do
      config = {"service_target" => {"service" => "*", "env" => "*"}, "k8s_target_v2" => {"cluster_targets" => ["c"]}}
      expect(remote.config_priority(config)).to eq(2)
    end

    it "ranks org-wide lowest (1)" do
      expect(remote.config_priority({"service_target" => {"service" => "*", "env" => "*"}})).to eq(1)
    end

    it "treats an absent service_target as org-wide (1)" do
      expect(remote.config_priority({})).to eq(1)
    end
  end

  describe "#merge_lib_configs" do
    it "takes the most-specific non-nil value per field (ordered most-specific first)" do
      ordered = [
        {"lib_config" => {"dynamic_instrumentation_enabled" => false}},
        {"lib_config" => {"dynamic_instrumentation_enabled" => true}},
      ]
      expect(remote.merge_lib_configs(ordered)).to eq("dynamic_instrumentation_enabled" => false)
    end

    it "inherits a field absent from the most-specific config from the next one" do
      ordered = [
        {"lib_config" => {"tracing_sampling_rate" => 0.5}},
        {"lib_config" => {"dynamic_instrumentation_enabled" => true}},
      ]
      expect(remote.merge_lib_configs(ordered)).to eq(
        "tracing_sampling_rate" => 0.5,
        "dynamic_instrumentation_enabled" => true,
      )
    end

    it "treats false as a winning value over an absent field" do
      ordered = [
        {"lib_config" => {"dynamic_instrumentation_enabled" => false}},
        {"lib_config" => {"tracing_sampling_rate" => 0.1}},
      ]
      expect(remote.merge_lib_configs(ordered)).to eq(
        "dynamic_instrumentation_enabled" => false,
        "tracing_sampling_rate" => 0.1,
      )
    end

    it "returns an empty hash for no configs" do
      expect(remote.merge_lib_configs([])).to eq({})
    end

    it "skips nil field values" do
      ordered = [{"lib_config" => {"x" => nil, "y" => 1}}]
      expect(remote.merge_lib_configs(ordered)).to eq("y" => 1)
    end

    it "skips a config whose lib_config is missing or not a hash" do
      ordered = [{"lib_config" => nil}, {}, {"lib_config" => {"x" => 1}}]
      expect(remote.merge_lib_configs(ordered)).to eq("x" => 1)
    end
  end

  describe "#merge_and_apply_configs" do
    def build_content(config_id, config)
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/APM_TRACING/#{config_id}/lib_config",
          content: JSON.dump(config),
        }
      )
    end

    let(:repository) { instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents) }

    before do
      allow(Datadog.configuration).to receive_messages(service: "web", env: "prod")
      allow(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
    end

    context "with cascading DI enablement configs" do
      let(:contents) do
        [
          build_content("org", {"service_target" => {"service" => "*", "env" => "*"},
                              "lib_config" => {"dynamic_instrumentation_enabled" => true}}),
          build_content("svc", {"service_target" => {"service" => "web", "env" => "prod"},
                              "lib_config" => {"dynamic_instrumentation_enabled" => false}}),
        ]
      end

      it "calls handle_rc_enablement once with the most-specific value and marks contents applied" do
        expect(Datadog::DI::Remote).to receive(:handle_rc_enablement).once.with(false, repository)
        allow(Datadog::SymbolDatabase::Remote).to receive(:deferred_products).and_return([])

        remote.merge_and_apply_configs(repository)

        expect(contents.map(&:apply_state)).to eq([2, 2])
      end
    end

    context "with equal-priority (org) configs setting the same field" do
      let(:contents) do
        [
          build_content("b", {"service_target" => {"service" => "*", "env" => "*"},
                            "lib_config" => {"dynamic_instrumentation_enabled" => true}}),
          build_content("a", {"service_target" => {"service" => "*", "env" => "*"},
                            "lib_config" => {"dynamic_instrumentation_enabled" => false}}),
        ]
      end

      it "breaks the tie by config id ascending (a before b)" do
        expect(Datadog::DI::Remote).to receive(:handle_rc_enablement).once.with(false, repository)
        allow(Datadog::SymbolDatabase::Remote).to receive(:deferred_products).and_return([])

        remote.merge_and_apply_configs(repository)
      end
    end

    context "when a config targets a different service" do
      let(:contents) do
        [
          build_content("other", {"service_target" => {"service" => "other", "env" => "prod"},
                                "lib_config" => {"dynamic_instrumentation_enabled" => true}}),
        ]
      end

      it "drops it from the merge but still marks it applied, and does not touch DI" do
        expect(Datadog::DI::Remote).not_to receive(:handle_rc_enablement)

        remote.merge_and_apply_configs(repository)

        expect(contents.first.apply_state).to eq(2)
      end
    end

    context "when remote.service overrides the local service for RC binding" do
      let(:contents) do
        [
          build_content("svc", {"service_target" => {"service" => "rc-svc", "env" => "*"},
                              "lib_config" => {"log_injection_enabled" => false}}),
        ]
      end

      before do
        # The RC client registers with the backend as remote.service ||
        # service, so a service-scoped config arrives targeted at the override.
        allow(Datadog.configuration.remote).to receive(:service).and_return("rc-svc")
      end

      it "matches the config against the override and applies it" do
        expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
          .with(contain_exactly(
            ["DD_LOGS_INJECTION", false],
            ["DD_TRACE_HEADER_TAGS", nil],
            ["DD_TRACE_SAMPLE_RATE", nil],
            ["DD_TRACE_SAMPLING_RULES", nil],
          ))

        remote.merge_and_apply_configs(repository)

        expect(contents.first.apply_state).to eq(2)
      end
    end

    context "when one config has malformed JSON" do
      let(:good) do
        build_content("good", {"service_target" => {"service" => "*", "env" => "*"}, "lib_config" => {}})
      end
      let(:bad) do
        Datadog::Core::Remote::Configuration::Content.parse(
          {
            path: "datadog/1/APM_TRACING/bad/lib_config",
            content: "{not json",
          }
        )
      end
      let(:contents) { [good, bad] }

      it "marks the malformed content errored, reports to telemetry, and still applies the good one" do
        expect(Datadog.send(:components).telemetry).to receive(:report)
          .with(kind_of(StandardError), description: "Failed to parse APM_TRACING remote config")

        remote.merge_and_apply_configs(repository)

        expect(good.apply_state).to eq(2)
        expect(bad.apply_state).to eq(3)
        expect(bad.apply_error).to include("JSON")
      end
    end

    context "when one config is valid JSON but not a JSON object" do
      let(:good) do
        build_content("good", {"service_target" => {"service" => "*", "env" => "*"},
                            "lib_config" => {"log_injection_enabled" => false}})
      end
      let(:non_object) do
        Datadog::Core::Remote::Configuration::Content.parse(
          {
            path: "datadog/1/APM_TRACING/non_object/lib_config",
            content: "null",
          }
        )
      end
      let(:contents) { [good, non_object] }

      it "marks the non-object content errored and still applies the good one" do
        expect(Datadog.send(:components).telemetry).to receive(:report)
          .with(kind_of(StandardError), description: "Failed to parse APM_TRACING remote config")

        remote.merge_and_apply_configs(repository)

        expect(good.apply_state).to eq(2)
        expect(non_object.apply_state).to eq(3)
        expect(non_object.apply_error).to include("object")
      end
    end

    context "with a non-APM_TRACING content present" do
      let(:other) do
        Datadog::Core::Remote::Configuration::Content.parse(
          {
            path: "datadog/1/OTHER_PRODUCT/x/name",
            content: "{}",
          }
        )
      end
      let(:apm) do
        build_content("org", {"service_target" => {"service" => "*", "env" => "*"}, "lib_config" => {}})
      end
      let(:contents) { [other, apm] }

      it "skips the non-APM_TRACING content and applies the APM_TRACING one" do
        remote.merge_and_apply_configs(repository)

        expect(apm.apply_state).to eq(2)
        expect(other.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::UNACKNOWLEDGED)
      end
    end

    context "with no APM_TRACING contents (last config removed)" do
      let(:contents) { [] }

      it "applies an empty merged config, resetting the dynamic options and not touching DI" do
        expect(Datadog::DI::Remote).not_to receive(:handle_rc_enablement)
        expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
          .with(contain_exactly(
            ["DD_LOGS_INJECTION", nil],
            ["DD_TRACE_HEADER_TAGS", nil],
            ["DD_TRACE_SAMPLE_RATE", nil],
            ["DD_TRACE_SAMPLING_RULES", nil],
          ))

        remote.merge_and_apply_configs(repository)
      end
    end

    context "when applying the merged config raises" do
      let(:contents) do
        [build_content("org", {"service_target" => {"service" => "*", "env" => "*"},
                            "lib_config" => {"dynamic_instrumentation_enabled" => true}})]
      end

      it "marks all parsed contents errored and reports to telemetry" do
        allow(Datadog::DI::Remote).to receive(:handle_rc_enablement).and_raise("boom")
        expect(Datadog.send(:components).telemetry).to receive(:report)
          .with(kind_of(StandardError), description: "Failed to apply APM_TRACING remote configs")

        remote.merge_and_apply_configs(repository)

        expect(contents.first.apply_state).to eq(3)
        expect(contents.first.apply_error).to include("boom")
      end
    end

    context "diagnostics" do
      let(:contents) do
        [
          build_content("org", {"service_target" => {"service" => "*", "env" => "*"}, "lib_config" => {}}),
          build_content("other", {"service_target" => {"service" => "other", "env" => "prod"}, "lib_config" => {}}),
        ]
      end

      it "emits the APM_TRACING RC diagnostic lines" do
        messages = []
        allow(Datadog.logger).to receive(:debug) { |*args, &blk| messages << (blk ? blk.call : args.first) }

        remote.merge_and_apply_configs(repository)

        expect(messages).to include(a_string_matching(/received 2 config\(s\)/))
        expect(messages).to include(a_string_matching(/config org scope=org priority=1/))
        expect(messages).to include(a_string_matching(/dropped config other/))
      end
    end
  end
end
