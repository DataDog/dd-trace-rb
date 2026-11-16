# frozen_string_literal: true

require "libddwaf"

require "datadog/appsec/spec_helper"

RSpec.describe Datadog::AppSec::SecurityEngine::Engine do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:appsec_settings) do
    settings = Datadog::Core::Configuration::Settings.new
    settings.appsec.enabled = true
    settings.appsec
  end

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(telemetry).to receive(:inc)
    allow(telemetry).to receive(:report)
  end

  describe ".new" do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    context "when libddwaf initializes correctly" do
      let(:default_ruleset) do
        {
          version: "2.2",
          metadata: {
            rules_version: "1.0.0",
          },
          rules: [
            {
              id: "rasp-003-001",
              name: "SQL Injection",
              tags: {
                type: "sql_injection",
                category: "exploit",
                module: "rasp",
              },
              conditions: [
                {
                  operator: "sqli_detector",
                  parameters: {
                    resource: [{address: "server.db.statement"}],
                    params: [{address: "server.request.query"}],
                    db_type: [{address: "server.db.system"}],
                  },
                },
              ],
              on_match: ["block-sqli"],
            },
          ],
        }
      end

      before do
        appsec_settings.ruleset = default_ruleset

        allow(Datadog.logger).to receive(:error)
        allow(telemetry).to receive(:report)
        allow(telemetry).to receive(:inc)
      end

      it "reports waf.init metric once with correct tags" do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.init", 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "1.0.0",
            success: "true",
          },
        )

        engine
      end
    end

    context "when libddwaf handle cannot be initialized" do
      before do
        appsec_settings.ruleset = {}

        allow(Datadog.logger).to receive(:error)
        allow(telemetry).to receive(:report)
        allow(telemetry).to receive(:inc)
      end

      it "reports error through telemetry" do
        expect(telemetry).to receive(:report).with(
          Datadog::AppSec::WAF::LibDDWAFError,
          description: "AppSec security engine failed to initialize",
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it "prints an error log message" do
        expect(Datadog.logger).to receive(:error).with(/AppSec security engine failed to initialize/)

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it "reports waf.init metric once with correct tags" do
        expect(telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.init", 1,
          tags: hash_including(success: "true"),
        )

        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.init", 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            success: "false",
          },
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end
    end

    context "when ruleset has errors" do
      before do
        appsec_settings.ruleset = {
          rules: [
            {
              id: "invalid-rule-id",
            },
          ],
        }

        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
        allow(telemetry).to receive(:report)
      end

      subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

      it "reports errors count through telemetry under appsec.waf.config_errors" do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          "waf.config_errors",
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            action: "init",
            config_key: "rules",
            scope: "item",
          },
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it "reports error through telemetry" do
        expect(telemetry).to receive(:error).with("missing key 'conditions': [invalid-rule-id]")

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it "prints an error log message" do
        expect(Datadog.logger).to receive(:error).with(/AppSec security engine failed to initialize/)

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it "reports waf.init metric once with correct tags" do
        expect(telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.init", 1,
          tags: hash_including(success: "true"),
        )

        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.init", 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            success: "false",
          },
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end
    end
  end

  describe "#new_runner" do
    let(:default_ruleset) do
      {
        version: "2.2",
        metadata: {
          rules_version: "1.0.0",
        },
        rules: [
          {
            id: "rasp-003-001",
            name: "SQL Injection",
            tags: {
              type: "sql_injection",
              category: "exploit",
              module: "rasp",
            },
            conditions: [
              {
                operator: "sqli_detector",
                parameters: {
                  resource: [{address: "server.db.statement"}],
                  params: [{address: "server.request.query"}],
                  db_type: [{address: "server.db.system"}],
                },
              },
            ],
            on_match: ["block-sqli"],
          },
        ],
      }
    end

    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    before do
      appsec_settings.ruleset = default_ruleset
    end

    it "returns an instance of SecurityEngine::Runner" do
      expect(engine.new_runner).to be_a(Datadog::AppSec::SecurityEngine::Runner)
    end

    it "sets waf_addresses" do
      expect(engine.new_runner.waf_addresses).to match_array(%w[server.db.statement server.request.query server.db.system])
    end

    it "sets ruleset_version" do
      expect(engine.new_runner.ruleset_version).to eq("1.0.0")
    end
  end

  describe "#add_or_update_config" do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    it "returns diagnostics with loaded config identifiers and no errors" do
      diagnostics = engine.add_or_update_config(
        {
          custom_rules: [
            {
              conditions: [{
                operator: "phrase_match",
                parameters: {inputs: [{address: "server.request.method"}], list: ["TEST"]},
              }],
              id: "test-custom-rule-id",
              name: "Test rule",
              tags: {category: "attack_attempt", custom: "1", type: "custom"},
              transformers: [],
            },
          ],
        },
        path: "datadog/603646/ASM/test-custom-rule",
      )

      aggregate_failures("diagnostics") do
        expect(diagnostics.dig("custom_rules", "errors")).to be_empty
        expect(diagnostics.dig("custom_rules", "loaded")).to eq(%w[test-custom-rule-id])
      end
    end

    context "when config loading fails with item-level errors" do
      let(:config_with_invalid_rule) do
        {
          custom_rules: [
            {
              conditions: [{
                operator: "phrase_match",
                parameters: {inputs: [{address: "server.request.method"}], list: ["TEST"]},
              }],
              id: "test-custom-rule-id",
              name: "Test rule",
              tags: {category: "attack_attempt", custom: "1", type: "custom"},
              transformers: [],
            },
            {
              id: "invalid-rule-one-id",
            },
            {
              id: "invalid-rule-two-id",
              conditions: [{
                operator: "phrase_match",
              }],
            },
          ],
        }
      end

      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it "returns diagnostics with loaded config identifiers and errors for invalid rules" do
        diagnostics = engine.add_or_update_config(config_with_invalid_rule, path: "datadog/603646/ASM/test-custom-rule")

        aggregate_failures("diagnostics") do
          expect(diagnostics.dig("custom_rules", "failed")).to match(%w[invalid-rule-one-id invalid-rule-two-id])
          expect(diagnostics.dig("custom_rules", "loaded")).to eq(%w[test-custom-rule-id])

          expect(diagnostics.dig("custom_rules", "errors")).to eq({
            "missing key 'conditions'" => %w[invalid-rule-one-id],
            "missing key 'parameters'" => %w[invalid-rule-two-id],
          })
        end
      end

      it "reports item-level errors count through telemetry" do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          "waf.config_errors",
          2,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            action: "update",
            config_key: "custom_rules",
            scope: "item",
          },
        )

        engine.add_or_update_config(config_with_invalid_rule, path: "datadog/603646/ASM/test-custom-rule")
      end

      it "reports item-level errors through telemetry" do
        expect(telemetry).to receive(:error).with("missing key 'conditions': [invalid-rule-one-id]")
        expect(telemetry).to receive(:error).with("missing key 'parameters': [invalid-rule-two-id]")

        engine.add_or_update_config(config_with_invalid_rule, path: "datadog/603646/ASM/test-custom-rule")
      end
    end

    context "when config loading fails with top-level error" do
      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it "returns nil for the rejected submission" do
        diagnostics = engine.add_or_update_config("", path: "datadog/603646/ASM/test-custom-rule")

        expect(diagnostics).to be_nil
      end

      it "reports top-level error count through telemetry" do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          "waf.config_errors",
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            action: "update",
            scope: "top-level",
          },
        )

        engine.add_or_update_config("", path: "datadog/603646/ASM/test-custom-rule")
      end

      it "reports top-level error through telemetry" do
        expect(telemetry).to receive(:error).with("invalid configuration type, expected 'map', obtained 'string'")

        engine.add_or_update_config("", path: "datadog/603646/ASM/test-custom-rule")
      end
    end

    context "when config loading fails with top-level error for some config key" do
      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it "returns nil for the rejected submission" do
        diagnostics = engine.add_or_update_config({custom_rules: ""}, path: "datadog/603646/ASM/test-custom-rule")

        expect(diagnostics).to be_nil
      end

      it "reports top-level error count through telemetry" do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          "waf.config_errors",
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "",
            action: "update",
            config_key: "custom_rules",
            scope: "top-level",
          },
        )

        engine.add_or_update_config({custom_rules: ""}, path: "datadog/603646/ASM/test-custom-rule")
      end

      it "reports top-level error through telemetry" do
        expect(telemetry).to receive(:error).with("bad cast, expected 'array', obtained 'string'")

        engine.add_or_update_config({custom_rules: ""}, path: "datadog/603646/ASM/test-custom-rule")
      end
    end

    context "when config path includes ASM_DD" do
      let(:asm_dd_config) do
        {
          version: "2.2",
          metadata: {
            rules_version: "1.0.0",
          },
          rules: [
            {
              id: "rasp-003-001",
              name: "SQL Injection",
              tags: {
                type: "sql_injection",
                category: "exploit",
                module: "rasp",
              },
              conditions: [
                {
                  operator: "sqli_detector",
                  parameters: {
                    resource: [{address: "server.db.statement"}],
                    params: [{address: "server.request.query"}],
                    db_type: [{address: "server.db.system"}],
                  },
                },
              ],
              on_match: ["block-sqli"],
            },
          ],
          actions: [
            {
              id: "block-sqli",
              type: "block",
              parameters: {
                status_code: "418",
                grpc_status_code: "42",
                type: "auto",
              },
            },
          ],
          processors: [],
        }
      end

      it "returns diagnostics with loaded rules identifiers and no errors" do
        diagnostics = engine.add_or_update_config(asm_dd_config, path: "datadog/603646/ASM_DD/latest/config")

        aggregate_failures("diagnostics") do
          expect(diagnostics.dig("rules", "loaded")).to eq(%w[rasp-003-001])
          expect(diagnostics.dig("rules", "errors")).to be_empty

          expect(diagnostics.dig("actions", "loaded")).to eq(%w[block-sqli])
          expect(diagnostics.dig("actions", "errors")).to be_empty

          expect(diagnostics.dig("processors", "errors")).to eq({})
        end
      end

      it "does not fall back when an individual processor fails to load" do
        config = asm_dd_config.merge(processors: [{id: "invalid-processor"}])

        expect(telemetry).to receive(:error).with("missing key 'generator': [invalid-processor]")

        diagnostics = engine.add_or_update_config(config, path: "datadog/603646/ASM_DD/latest/config")

        expect(diagnostics.dig("processors", "failed")).to eq(%w[invalid-processor])
        expect(diagnostics["ruleset_version"]).to eq("1.0.0")
      end

      it "reloads default rules without conflicts when the processor section fails to load" do
        appsec_settings.ruleset = asm_dd_config

        expect(telemetry).to receive(:error).with("bad cast, expected 'array', obtained 'string'")

        diagnostics = engine.add_or_update_config(
          asm_dd_config.merge(processors: ""),
          path: "datadog/603646/ASM_DD/latest/config",
        )

        expect(diagnostics).to be_nil
        engine.reconfigure!
        runner = engine.new_runner
        expect(runner.waf_addresses).to match_array(%w[server.db.statement server.request.query server.db.system])
        runner.finalize!
      end

      it "removes default config before adding new config" do
        engine.add_or_update_config(asm_dd_config, path: "datadog/603646/ASM_DD/latest/config")
        engine.reconfigure!

        expect(engine.new_runner.waf_addresses).to match_array(%w[server.db.statement server.request.query server.db.system])
      end

      it "updates ruleset_version" do
        engine.add_or_update_config(asm_dd_config, path: "datadog/603646/ASM_DD/latest/config")
        engine.reconfigure!

        expect(engine.new_runner.ruleset_version).to eq("1.0.0")
      end

      context "when adding of config fails" do
        let(:invalid_config) do
          {
            rules: "",
          }
        end

        before do
          allow(telemetry).to receive(:inc)
          allow(telemetry).to receive(:error)
        end

        it "reports errors count through telemetry under appsec.waf.config_errors" do
          expect(telemetry).to receive(:inc).with(
            Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
            "waf.config_errors",
            1,
            tags: {
              waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
              event_rules_version: "",
              action: "update",
              config_key: "rules",
              scope: "top-level",
            },
          )

          engine.add_or_update_config(invalid_config, path: "datadog/603646/ASM_DD/latest/config")
        end

        it "reports errors through telemetry" do
          expect(telemetry).to receive(:error).with("bad cast, expected 'array', obtained 'string'")

          engine.add_or_update_config(invalid_config, path: "datadog/603646/ASM_DD/latest/config")
        end

        it "adds default config back" do
          expect do
            engine.add_or_update_config(invalid_config, path: "datadog/603646/ASM_DD/latest/config")
            engine.reconfigure!
          end.not_to change { engine.new_runner.waf_addresses.sort }
        end

        it "does not change ruleset_version" do
          expect do
            engine.add_or_update_config(invalid_config, path: "datadog/603646/ASM_DD/latest/config")
            engine.reconfigure!
          end.not_to change { engine.new_runner.ruleset_version }
        end
      end
    end
  end

  describe "#remove_config_at_path" do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    let(:custom_rules_config) do
      {
        custom_rules: [
          {
            conditions: [{
              operator: "phrase_match",
              parameters: {inputs: [{address: "server.request.method"}], list: ["TEST"]},
            }],
            id: "test-custom-rule-id",
            name: "Test rule",
            tags: {category: "attack_attempt", custom: "2", type: "custom"},
            transformers: [],
          },
        ],
      }
    end

    before do
      engine.add_or_update_config(custom_rules_config, path: "datadog/603646/ASM/test-custom-rule")
    end

    it "returns true for a path for which a config was loaded before" do
      expect(engine.remove_config_at_path("datadog/603646/ASM/test-custom-rule")).to eq(true)
    end

    it "returns false for a path for which a config was not loaded before" do
      expect(engine.remove_config_at_path("datadog/603646/ASM/something")).to eq(false)
    end

    context "when config path includes ASM_DD" do
      it "adds default config back" do
        appsec_settings.ruleset = {
          version: "2.2",
          metadata: {rules_version: "1.0.1"},
          rules: [{
            id: "rasp-934-100",
            name: "Server-side request forgery exploit",
            tags: {
              type: "ssrf",
              category: "vulnerability_trigger",
              module: "rasp",
            },
            conditions: [
              {
                parameters: {
                  resource: [{address: "server.io.net.url"}],
                  params: [
                    {address: "server.request.query"},
                    {address: "server.request.body"},
                    {address: "server.request.path_params"},
                  ],
                },
                operator: "ssrf_detector",
              },
            ],
            on_match: ["stack_trace"],
          }],
        }
        engine = described_class.new(appsec_settings: appsec_settings, telemetry: telemetry)

        engine.add_or_update_config(
          {
            version: "2.2",
            metadata: {rules_version: "1.0.0"},
            rules: [
              {
                id: "rasp-003-001",
                name: "SQL Injection",
                tags: {
                  type: "sql_injection",
                  category: "exploit",
                  module: "rasp",
                },
                conditions: [
                  {
                    operator: "sqli_detector",
                    parameters: {
                      resource: [{address: "server.db.statement"}],
                      params: [{address: "server.request.query"}],
                      db_type: [{address: "server.db.system"}],
                    },
                  },
                ],
                on_match: ["block-sqli"],
              },
            ],
          },
          path: "datadog/603646/ASM_DD/latest/config",
        )
        engine.reconfigure!

        expect do
          engine.remove_config_at_path("datadog/603646/ASM_DD/latest/config")
          engine.reconfigure!
        end.to(
          change { engine.new_runner.waf_addresses }
            .from(match_array(%w[server.db.statement server.request.query server.db.system]))
            .to(match_array(%w[server.io.net.url server.request.query server.request.body server.request.path_params])),
        )
      end
    end
  end

  describe "#reconfigure!" do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    let(:asm_dd_config) do
      {
        version: "2.2",
        metadata: {
          rules_version: "1.0.0",
        },
        rules: [
          {
            id: "rasp-003-001",
            name: "SQL Injection",
            tags: {
              type: "sql_injection",
              category: "exploit",
              module: "rasp",
            },
            conditions: [
              {
                operator: "sqli_detector",
                parameters: {
                  resource: [{address: "server.db.statement"}],
                  params: [{address: "server.request.query"}],
                  db_type: [{address: "server.db.system"}],
                },
              },
            ],
            on_match: ["block-sqli"],
          },
        ],
      }
    end

    before do
      engine.add_or_update_config(asm_dd_config, path: "datadog/603646/ASM_DD/latest/config")
    end

    it "updates waf_addresses" do
      expect { engine.reconfigure! }.to(change { engine.new_runner.waf_addresses })
    end

    it "reports waf.updates metric with success: true" do
      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.updates", 1,
        tags: {
          waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
          event_rules_version: "1.0.0",
          success: "true",
        },
      )

      engine.reconfigure!
    end

    context "when a new handle cannot be build" do
      let(:asm_dd_config) do
        {
          version: "2.2",
          metadata: {
            rules_version: "2.0.0",
          },
          rules: [],
        }
      end

      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
        allow(telemetry).to receive(:report)
      end

      it "does not change waf_addresses" do
        expect { engine.reconfigure! }.not_to(change { engine.new_runner.waf_addresses.sort })
      end

      it "reports error through telemetry" do
        expect(telemetry).to receive(:report).with(
          Datadog::AppSec::WAF::LibDDWAFError,
          description: "AppSec security engine failed to reconfigure, reverting to the previous configuration",
        )

        engine.reconfigure!
      end

      it "reports waf.updates metric with success: false" do
        expect(Datadog::AppSec.telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.updates", 1,
          tags: hash_including(success: "true"),
        )

        expect(Datadog::AppSec.telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "waf.updates", 1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: "2.0.0",
            success: "false",
          },
        )

        engine.reconfigure!
      end
    end
  end
  describe "configuration failure recovery" do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    let(:builder) { Datadog::AppSec::WAF::HandleBuilder.new }
    let(:oversized_config) { {"rules" => Array.new(65_536)} }
    let(:remote_path) { "datadog/603646/ASM_DD/test/config" }
    let(:handles) { [] }

    before do
      builder
      allow(Datadog::AppSec::WAF::HandleBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:build_handle).and_wrap_original do |original|
        handle = original.call
        handles << handle
        handle
      end
      allow(telemetry).to receive(:error)
    end

    after do
      handles.each(&:finalize!)
      builder.finalize!
    end

    it "warns once and fails initialization for a real conversion error" do
      appsec_settings.ruleset = oversized_config
      expect(Datadog.logger).to receive(:warn).with(/ASM_DD\/default: Array exceeds the native size limit/).once
      expect(telemetry).to receive(:inc).with("appsec", "waf.init", 1, tags: hash_including(success: "false"))
      expect { engine }.to raise_error(Datadog::AppSec::WAF::ConversionError)
    end

    it "warns for conversion during obfuscator construction" do
      allow(Datadog::AppSec::WAF::HandleBuilder).to receive(:new)
        .and_raise(Datadog::AppSec::WAF::ConversionError, "obfuscator conversion failed")
      expect(Datadog.logger).to receive(:warn).with(/libddwaf-rb\/obfuscator: obfuscator conversion failed/).once
      expect { engine }.to raise_error(Datadog::AppSec::WAF::ConversionError)
    end

    it "warns for conversion during removal and reports failure explicitly" do
      engine
      allow(builder).to receive(:remove_config_at_path).with(remote_path)
        .and_raise(Datadog::AppSec::WAF::ConversionError, "removal conversion failed")
      expect(Datadog.logger).to receive(:warn).with(/#{Regexp.escape(remote_path)}: removal conversion failed/).once
      expect(engine.remove_config_at_path(remote_path)).to be_nil
    end

    it "rejects conversion-failed input and reports a successful fallback update" do
      engine
      expect(Datadog.logger).to receive(:warn).with(/#{Regexp.escape(remote_path)}: Array exceeds the native size limit/).once
      expect(engine.add_or_update_config(oversized_config, path: remote_path)).to be_nil
      expect(telemetry).to receive(:inc).with("appsec", "waf.updates", 1, tags: hash_including(success: "true"))
      engine.reconfigure!
      expect(handles.size).to eq(2)
      expect(handles.last.known_addresses).to match_array(handles.first.known_addresses)
    end

    it "rejects a false success flag even with empty diagnostics" do
      engine
      allow(builder).to receive(:add_or_update_config).with({}, path: "ASM/test").and_return(
        Datadog::AppSec::WAF::ConfigurationResult.new(success: false, diagnostics: {}),
      )
      expect(engine.add_or_update_config({}, path: "ASM/test")).to be_nil
      expect(telemetry).to receive(:inc).with("appsec", "waf.updates", 1, tags: hash_including(success: "true"))
      engine.reconfigure!
      expect(telemetry).to receive(:inc).with("appsec", "waf.updates", 1, tags: hash_including(success: "true"))
      engine.reconfigure!
    end

    it "routes opaque non-hash diagnostics through configuration failure" do
      engine
      allow(builder).to receive(:add_or_update_config).with({}, path: "ASM/test").and_return(
        Datadog::AppSec::WAF::ConfigurationResult.new(success: true, diagnostics: nil),
      )
      expect(telemetry).to receive(:report).with(
        an_instance_of(Datadog::AppSec::WAF::LibDDWAFError), description: /ASM\/test/,
      )
      expect(engine.add_or_update_config({}, path: "ASM/test")).to be_nil
    end

    [:rejection, :removal].each do |operation|
      it "keeps the active handle after #{operation} reload fails, until replacement rules recover" do
        engine
        rules = Datadog::AppSec::Processor::RuleLoader.load_rules(telemetry: telemetry, ruleset: :recommended)
        engine.add_or_update_config(rules, path: remote_path) if operation == :removal
        allow(builder).to receive(:add_or_update_config).and_call_original
        allow(builder).to receive(:add_or_update_config).with(anything, path: "ASM_DD/default")
          .and_raise(Datadog::AppSec::WAF::ConversionError, "reload conversion failed")
        expect(Datadog.logger).to receive(:warn).with(/ASM_DD\/default: reload conversion failed/).once
        if operation == :removal
          expect(engine.remove_config_at_path(remote_path)).to be_nil
        else
          expect(engine.add_or_update_config("invalid", path: remote_path)).to be_nil
        end
        engine.reconfigure!
        engine.reconfigure!
        expect(handles.size).to eq(1)

        recovery_path = if operation == :rejection
          "ASM_DD/default"
        else
          remote_path
        end
        allow(builder).to receive(:add_or_update_config).with(anything, path: recovery_path).and_call_original
        expect(engine.add_or_update_config(rules, path: recovery_path)).not_to be_nil
        expect(builder).to receive(:build_handle).and_wrap_original do |original|
          handle = original.call
          handles << handle
          handle
        end
        expect(telemetry).to receive(:inc).with("appsec", "waf.updates", 1, tags: hash_including(success: "true"))
        engine.reconfigure!
      end
    end
  end
end
