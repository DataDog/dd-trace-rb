# frozen_string_literal: true

require 'libddwaf'

require 'datadog/appsec/spec_helper'

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
  end

  describe '.new' do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    context 'when libddwaf initializes correctly' do
      let(:default_ruleset) do
        {
          version: '2.2',
          metadata: {
            rules_version: '1.0.0'
          },
          rules: [
            {
              id: 'rasp-003-001',
              name: 'SQL Injection',
              tags: {
                type: 'sql_injection',
                category: 'exploit',
                module: 'rasp'
              },
              conditions: [
                {
                  operator: 'sqli_detector',
                  parameters: {
                    resource: [{address: 'server.db.statement'}],
                    params: [{address: 'server.request.query'}],
                    db_type: [{address: 'server.db.system'}]
                  }
                }
              ],
              on_match: ['block-sqli']
            }
          ]
        }
      end

      before do
        appsec_settings.ruleset = default_ruleset

        allow(Datadog.logger).to receive(:error)
        allow(telemetry).to receive(:report)
        allow(telemetry).to receive(:inc)
      end

      it 'reports waf.init metric once with correct tags' do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.init', 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '1.0.0',
            success: true
          }
        ).once

        engine
      end
    end

    context 'when libddwaf handle cannot be initialized' do
      before do
        appsec_settings.ruleset = {}

        allow(Datadog.logger).to receive(:error)
        allow(telemetry).to receive(:report)
        allow(telemetry).to receive(:inc)
      end

      it 'reports error though telemetry' do
        expect(telemetry).to receive(:report).with(
          Datadog::AppSec::WAF::LibDDWAFError,
          description: 'AppSec security engine failed to initialize'
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it 'prints an error log message' do
        expect(Datadog.logger).to receive(:error).with(/AppSec security engine failed to initialize/)

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it 'reports waf.init metric once with correct tags' do
        expect(telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.init', 1,
          tags: hash_including(success: true)
        )

        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.init', 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            success: false
          }
        ).once

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end
    end

    context 'when ruleset has errors' do
      before do
        appsec_settings.ruleset = {
          rules: [
            {
              id: 'invalid-rule-id'
            }
          ]
        }

        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
        allow(telemetry).to receive(:report)
      end

      subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

      it 'reports errors count through telemetry under appsec.waf.config_errors' do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          'waf.config_errors',
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            action: 'init',
            config_key: 'rules',
            scope: 'item'
          }
        )

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it 'reports error though telemetry' do
        expect(telemetry).to receive(:error).with("missing key 'conditions': [invalid-rule-id]")

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it 'prints an error log message' do
        expect(Datadog.logger).to receive(:error).with(/AppSec security engine failed to initialize/)

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end

      it 'reports waf.init metric once with correct tags' do
        expect(telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.init', 1,
          tags: hash_including(success: true)
        )

        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.init', 1, tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            success: false
          }
        ).once

        expect { engine }.to raise_error(Datadog::AppSec::WAF::LibDDWAFError)
      end
    end
  end

  describe '#new_runner' do
    let(:default_ruleset) do
      {
        version: '2.2',
        metadata: {
          rules_version: '1.0.0'
        },
        rules: [
          {
            id: 'rasp-003-001',
            name: 'SQL Injection',
            tags: {
              type: 'sql_injection',
              category: 'exploit',
              module: 'rasp'
            },
            conditions: [
              {
                operator: 'sqli_detector',
                parameters: {
                  resource: [{address: 'server.db.statement'}],
                  params: [{address: 'server.request.query'}],
                  db_type: [{address: 'server.db.system'}]
                }
              }
            ],
            on_match: ['block-sqli']
          }
        ]
      }
    end

    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    before do
      appsec_settings.ruleset = default_ruleset
    end

    it 'returns an instance of SecurityEngine::Runner' do
      expect(engine.new_runner).to be_a(Datadog::AppSec::SecurityEngine::Runner)
    end

    it 'sets waf_addresses' do
      expect(engine.new_runner.waf_addresses).to match_array(%w[server.db.statement server.request.query server.db.system])
    end

    it 'sets ruleset_version' do
      expect(engine.new_runner.ruleset_version).to eq('1.0.0')
    end
  end

  describe '#add_or_update_config' do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    it 'returns diagnostics with loaded config identifiers and no errors' do
      diagnostics = engine.add_or_update_config(
        {
          custom_rules: [
            {
              conditions: [{
                operator: 'phrase_match',
                parameters: {inputs: [{address: 'server.request.method'}], list: ['TEST']}
              }],
              id: 'test-custom-rule-id',
              name: 'Test rule',
              tags: {category: 'attack_attempt', custom: '1', type: 'custom'},
              transformers: []
            }
          ]
        },
        path: 'datadog/603646/ASM/test-custom-rule'
      )

      aggregate_failures('diagnostics') do
        expect(diagnostics.dig('custom_rules', 'errors')).to be_empty
        expect(diagnostics.dig('custom_rules', 'loaded')).to eq(%w[test-custom-rule-id])
      end
    end

    context 'when config loading fails with item-level errors' do
      let(:config_with_invalid_rule) do
        {
          custom_rules: [
            {
              conditions: [{
                operator: 'phrase_match',
                parameters: {inputs: [{address: 'server.request.method'}], list: ['TEST']}
              }],
              id: 'test-custom-rule-id',
              name: 'Test rule',
              tags: {category: 'attack_attempt', custom: '1', type: 'custom'},
              transformers: []
            },
            {
              id: 'invalid-rule-one-id'
            },
            {
              id: 'invalid-rule-two-id',
              conditions: [{
                operator: 'phrase_match'
              }]
            }
          ]
        }
      end

      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it 'returns diagnostics with loaded config identifiers and errors for invalid rules' do
        diagnostics = engine.add_or_update_config(config_with_invalid_rule, path: 'datadog/603646/ASM/test-custom-rule')

        aggregate_failures('diagnostics') do
          expect(diagnostics.dig('custom_rules', 'failed')).to match(%w[invalid-rule-one-id invalid-rule-two-id])
          expect(diagnostics.dig('custom_rules', 'loaded')).to eq(%w[test-custom-rule-id])

          expect(diagnostics.dig('custom_rules', 'errors')).to eq({
            "missing key 'conditions'" => %w[invalid-rule-one-id],
            "missing key 'parameters'" => %w[invalid-rule-two-id]
          })
        end
      end

      it 'reports item-level errors count through telemetry' do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          'waf.config_errors',
          2,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            action: 'update',
            config_key: 'custom_rules',
            scope: 'item'
          }
        )

        engine.add_or_update_config(config_with_invalid_rule, path: 'datadog/603646/ASM/test-custom-rule')
      end

      it 'reports item-level errors through telemetry' do
        expect(telemetry).to receive(:error).with("missing key 'conditions': [invalid-rule-one-id]")
        expect(telemetry).to receive(:error).with("missing key 'parameters': [invalid-rule-two-id]")

        engine.add_or_update_config(config_with_invalid_rule, path: 'datadog/603646/ASM/test-custom-rule')
      end
    end

    context 'when config loading fails with top-level error' do
      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it 'returns diagnostics with loaded config identifiers and errors for invalid rules' do
        diagnostics = engine.add_or_update_config('', path: 'datadog/603646/ASM/test-custom-rule')

        expect(diagnostics.fetch('error')).to eq("invalid configuration type, expected 'map', obtained 'string'")
      end

      it 'reports top-level error count through telemetry' do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          'waf.config_errors',
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            action: 'update',
            scope: 'top-level'
          }
        )

        engine.add_or_update_config('', path: 'datadog/603646/ASM/test-custom-rule')
      end

      it 'reports top-level error through telemetry' do
        expect(telemetry).to receive(:error).with("invalid configuration type, expected 'map', obtained 'string'")

        engine.add_or_update_config('', path: 'datadog/603646/ASM/test-custom-rule')
      end
    end

    context 'when config loading fails with top-level error for some config key' do
      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
      end

      it 'returns diagnostics with loaded config identifiers and errors for invalid rules' do
        diagnostics = engine.add_or_update_config({custom_rules: ''}, path: 'datadog/603646/ASM/test-custom-rule')

        aggregate_failures('diagnostics') do
          expect(diagnostics).not_to have_key('error')
          expect(diagnostics.dig('custom_rules', 'error')).to eq("bad cast, expected 'array', obtained 'string'")
        end
      end

      it 'reports top-level error count through telemetry' do
        expect(telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
          'waf.config_errors',
          1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '',
            action: 'update',
            config_key: 'custom_rules',
            scope: 'top-level'
          }
        )

        engine.add_or_update_config({custom_rules: ''}, path: 'datadog/603646/ASM/test-custom-rule')
      end

      it 'reports top-level error through telemetry' do
        expect(telemetry).to receive(:error).with("bad cast, expected 'array', obtained 'string'")

        engine.add_or_update_config({custom_rules: ''}, path: 'datadog/603646/ASM/test-custom-rule')
      end
    end

    context 'when config path includes ASM_DD' do
      let(:asm_dd_config) do
        {
          version: '2.2',
          metadata: {
            rules_version: '1.0.0'
          },
          rules: [
            {
              id: 'rasp-003-001',
              name: 'SQL Injection',
              tags: {
                type: 'sql_injection',
                category: 'exploit',
                module: 'rasp'
              },
              conditions: [
                {
                  operator: 'sqli_detector',
                  parameters: {
                    resource: [{address: 'server.db.statement'}],
                    params: [{address: 'server.request.query'}],
                    db_type: [{address: 'server.db.system'}]
                  }
                }
              ],
              on_match: ['block-sqli']
            }
          ],
          actions: [
            {
              id: 'block-sqli',
              type: 'block',
              parameters: {
                status_code: '418',
                grpc_status_code: '42',
                type: 'auto'
              }
            }
          ]
        }
      end

      it 'returns diagnostics with loaded rules identifiers and no errors' do
        diagnostics = engine.add_or_update_config(asm_dd_config, path: 'datadog/603646/ASM_DD/latest/config')

        aggregate_failures('diagnostics') do
          expect(diagnostics.dig('rules', 'loaded')).to eq(%w[rasp-003-001])
          expect(diagnostics.dig('rules', 'errors')).to be_empty

          expect(diagnostics.dig('actions', 'loaded')).to eq(%w[block-sqli])
          expect(diagnostics.dig('actions', 'errors')).to be_empty
        end
      end

      it 'removes default config before adding new config' do
        engine.add_or_update_config(asm_dd_config, path: 'datadog/603646/ASM_DD/latest/config')
        engine.reconfigure!

        expect(engine.new_runner.waf_addresses).to match_array(%w[server.db.statement server.request.query server.db.system])
      end

      it 'updates ruleset_version' do
        engine.add_or_update_config(asm_dd_config, path: 'datadog/603646/ASM_DD/latest/config')
        engine.reconfigure!

        expect(engine.new_runner.ruleset_version).to eq('1.0.0')
      end

      context 'when adding of config fails' do
        let(:invalid_config) do
          {
            rules: ''
          }
        end

        before do
          allow(telemetry).to receive(:inc)
          allow(telemetry).to receive(:error)
        end

        it 'reports errors count through telemetry under appsec.waf.config_errors' do
          expect(telemetry).to receive(:inc).with(
            Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE,
            'waf.config_errors',
            1,
            tags: {
              waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
              event_rules_version: '',
              action: 'update',
              config_key: 'rules',
              scope: 'top-level'
            }
          )

          engine.add_or_update_config(invalid_config, path: 'datadog/603646/ASM_DD/latest/config')
        end

        it 'reports errors through telemetry' do
          expect(telemetry).to receive(:error).with("bad cast, expected 'array', obtained 'string'")

          engine.add_or_update_config(invalid_config, path: 'datadog/603646/ASM_DD/latest/config')
        end

        it 'adds default config back' do
          expect do
            engine.add_or_update_config(invalid_config, path: 'datadog/603646/ASM_DD/latest/config')
            engine.reconfigure!
          end.not_to change { engine.new_runner.waf_addresses }
        end

        it 'does not change ruleset_version' do
          expect do
            engine.add_or_update_config(invalid_config, path: 'datadog/603646/ASM_DD/latest/config')
            engine.reconfigure!
          end.not_to change { engine.new_runner.ruleset_version }
        end
      end
    end
  end

  describe '#remove_config_at_path' do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    let(:custom_rules_config) do
      {
        custom_rules: [
          {
            conditions: [{
              operator: 'phrase_match',
              parameters: {inputs: [{address: 'server.request.method'}], list: ['TEST']}
            }],
            id: 'test-custom-rule-id',
            name: 'Test rule',
            tags: {category: 'attack_attempt', custom: '2', type: 'custom'},
            transformers: []
          }
        ]
      }
    end

    before do
      engine.add_or_update_config(custom_rules_config, path: 'datadog/603646/ASM/test-custom-rule')
    end

    it 'returns true for a path for which a config was loaded before' do
      expect(engine.remove_config_at_path('datadog/603646/ASM/test-custom-rule')).to eq(true)
    end

    it 'returns false for a path for which a config was not loaded before' do
      expect(engine.remove_config_at_path('datadog/603646/ASM/something')).to eq(false)
    end

    context 'when config path includes ASM_DD' do
      it 'adds default config back' do
        appsec_settings.ruleset = {
          version: '2.2',
          metadata: {rules_version: '1.0.1'},
          rules: [{
            id: 'rasp-934-100',
            name: 'Server-side request forgery exploit',
            tags: {
              type: 'ssrf',
              category: 'vulnerability_trigger',
              module: 'rasp'
            },
            conditions: [
              {
                parameters: {
                  resource: [{address: 'server.io.net.url'}],
                  params: [
                    {address: 'server.request.query'},
                    {address: 'server.request.body'},
                    {address: 'server.request.path_params'}
                  ]
                },
                operator: 'ssrf_detector'
              }
            ],
            on_match: ['stack_trace']
          }]
        }
        engine = described_class.new(appsec_settings: appsec_settings, telemetry: telemetry)

        engine.add_or_update_config(
          {
            version: '2.2',
            metadata: {rules_version: '1.0.0'},
            rules: [
              {
                id: 'rasp-003-001',
                name: 'SQL Injection',
                tags: {
                  type: 'sql_injection',
                  category: 'exploit',
                  module: 'rasp'
                },
                conditions: [
                  {
                    operator: 'sqli_detector',
                    parameters: {
                      resource: [{address: 'server.db.statement'}],
                      params: [{address: 'server.request.query'}],
                      db_type: [{address: 'server.db.system'}]
                    }
                  }
                ],
                on_match: ['block-sqli']
              }
            ]
          },
          path: 'datadog/603646/ASM_DD/latest/config'
        )
        engine.reconfigure!

        expect do
          engine.remove_config_at_path('datadog/603646/ASM_DD/latest/config')
          engine.reconfigure!
        end.to(
          change { engine.new_runner.waf_addresses }
            .from(match_array(%w[server.db.statement server.request.query server.db.system]))
            .to(match_array(%w[server.io.net.url server.request.query server.request.body server.request.path_params]))
        )
      end
    end
  end

  describe '#reconfigure!' do
    subject(:engine) { described_class.new(appsec_settings: appsec_settings, telemetry: telemetry) }

    let(:asm_dd_config) do
      {
        version: '2.2',
        metadata: {
          rules_version: '1.0.0'
        },
        rules: [
          {
            id: 'rasp-003-001',
            name: 'SQL Injection',
            tags: {
              type: 'sql_injection',
              category: 'exploit',
              module: 'rasp'
            },
            conditions: [
              {
                operator: 'sqli_detector',
                parameters: {
                  resource: [{address: 'server.db.statement'}],
                  params: [{address: 'server.request.query'}],
                  db_type: [{address: 'server.db.system'}]
                }
              }
            ],
            on_match: ['block-sqli']
          }
        ]
      }
    end

    before do
      engine.add_or_update_config(asm_dd_config, path: 'datadog/603646/ASM_DD/latest/config')
    end

    it 'updates waf_addresses' do
      expect { engine.reconfigure! }.to(change { engine.new_runner.waf_addresses })
    end

    it 'reports waf.updates metric with success: true' do
      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.updates', 1,
        tags: {
          waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
          event_rules_version: '1.0.0',
          success: true
        }
      ).once

      engine.reconfigure!
    end

    context 'when a new handle cannot be build' do
      let(:asm_dd_config) do
        {
          version: '2.2',
          metadata: {
            rules_version: '2.0.0'
          },
          rules: []
        }
      end

      before do
        allow(telemetry).to receive(:inc)
        allow(telemetry).to receive(:error)
        allow(telemetry).to receive(:report)
      end

      it 'does not change waf_addresses' do
        expect { engine.reconfigure! }.not_to(change { engine.new_runner.waf_addresses })
      end

      it 'reports error though telemetry' do
        expect(telemetry).to receive(:report).with(
          Datadog::AppSec::WAF::LibDDWAFError,
          description: 'AppSec security engine failed to reconfigure, reverting to the previous configuration'
        )

        engine.reconfigure!
      end

      it 'reports waf.updates metric with success: false' do
        expect(Datadog::AppSec.telemetry).not_to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.updates', 1,
          tags: hash_including(success: true)
        )

        expect(Datadog::AppSec.telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.updates', 1,
          tags: {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: '2.0.0',
            success: false
          }
        ).once

        engine.reconfigure!
      end
    end
  end
end
