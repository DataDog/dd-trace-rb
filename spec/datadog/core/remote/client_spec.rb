# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/transport/http'
require 'datadog/core/remote/client'

RSpec.describe Datadog::Core::Remote::Client do
  shared_context 'HTTP connection stub' do
    before do
      request_class = ::Net::HTTP::Post
      http_request = instance_double(request_class)
      allow(http_request).to receive(:body=)
      allow(request_class).to receive(:new).and_return(http_request)

      allow(::Net::HTTP).to receive(:new).and_return(http_connection)

      allow(http_connection).to receive(:open_timeout=)
      allow(http_connection).to receive(:read_timeout=)
      allow(http_connection).to receive(:use_ssl=)

      allow(http_connection).to receive(:start).and_yield(http_connection)
      http_response = instance_double(::Net::HTTPResponse, body: response_body, code: response_code)
      allow(http_connection).to receive(:request).with(http_request).and_return(http_response)
    end
  end

  shared_context 'Client dispatches changes' do
    # This expectation helps us ensure the client wors as expected
    # and avoid propagated changes via the dispacther that usally
    # lead to components reconfiguration. Causing flaky tests.
    before do
      expect(client.dispatcher).to receive(:dispatch).with(
        instance_of(Datadog::Core::Remote::Configuration::Repository::ChangeSet),
        client.repository
      ).at_least(:once)
    end
  end

  let(:http_connection) { instance_double(::Net::HTTP) }
  let(:transport) { Datadog::Core::Remote::Transport::HTTP.v7(&proc { |_client| }) }
  let(:roots) do
    [
      {
        'signatures' => [
          {
            'keyid' => 'bla1',
            'sig' => 'fake sig'
          },
        ],
        'signed' => {
          '_type' => 'root',
          'consistent_snapshot' => true,
          'expires' => '2022-02-01T00:00:00Z',
          'keys' => {
            'foo' => {
              'keyid_hash_algorithms' => ['sha256', 'sha512'],
              'keytype' => 'ed25519',
              'keyval' => {
                'public' => 'blabla'
              },
              'scheme' => 'ed25519'
            }
          },
          'roles' => {
            'root' => {
              'keyids' => ['bla1',
                           'bla2'],
              'threshold' => 2
            },
            'snapshot' => {
              'keyids' => ['foo'],
              'threshold' => 1 \
            },
            'targets' => { \
              'keyids' => ['foo'],
              'threshold' => 1 \
            },
            'timestamp' => {
              'keyids' => ['foo'],
              'threshold' => 1
            }
          },
          'spec_version' => '1.0',
          'version' => 2
        }
      },
    ]
  end

  let(:exclusions_filter_content) do
    {
      'datadog/603646/ASM/exclusion_filters/config' => {
        'custom' => {
          'c' => ['client_id'],
          'tracer-predicates' => {
            'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }]
          },
          'v' => 21
        },
        'hashes' => { 'sha256' => Digest::SHA256.hexdigest(exclusions) },
        'length' => 645
      }
    }
  end

  let(:blocked_ips_content) do
    {
      'datadog/603646/ASM_DATA/blocked_ips/config' => {
        'custom' => {
          'c' => ['client_id'],
          'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }] },
          'v' => 51
        },
        'hashes' => { 'sha256' => Digest::SHA256.hexdigest(blocked_ips) },
        'length' => 1834
      },
    }
  end

  let(:rules_content) do
    {
      'datadog/603646/ASM_DD/latest/config' => {
        'custom' => {
          'c' => ['client_id'],
          'tracer-predicates' => {
            'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }]
          },
          'v' => 21
        },
        'hashes' => { 'sha256' => Digest::SHA256.hexdigest(rules_data) },
        'length' => 645
      },
    }
  end

  let(:target_content) { {} }

  let(:targets) do
    {
      'signatures' => [
        {
          'keyid' => 'hello',
          'sig' => 'sig'
        }
      ],
      'signed' => {
        '_type' => 'targets',
        'custom' => {
          'agent_refresh_interval' => 50,
          'opaque_backend_state' => 'iuycygweiuegciwbiecwbicw'
        },
        'expires' => '2023-06-17T10:16:42Z',
        'spec_version' => '1.0.0',
        'targets' => target_content,
        'version' => 46915439
      }
    }
  end

  let(:exclusions) do
    '{"exclusions":[{"conditions":[{"operator":"ip_match","parameters":{"inputs":[{"address":"http.client_ip"}]}}]}]}'
  end

  let(:blocked_ips) do
    '{"rules_data":[{"data":[{"expiration":1678972458,"value":"42.42.42.1"}]}]}'
  end

  let(:rules_data) do
    {
      version: '2.2',
      metadata: {
        rules_version: '1.5.2'
      },
      rules: [
        {
          id: 'blk-001-001',
          name: 'Block IP Addresses',
          tags: {
            type: 'block_ip',
            category: 'security_response'
          },
          conditions: [
            {
              parameters: {
                inputs: [
                  {
                    address: 'http.client_ip'
                  }
                ],
                data: 'blocked_ips'
              },
              operator: 'ip_match'
            }
          ],
          transformers: [],
          on_match: [
            'block'
          ]
        }
      ]
    }.to_json
  end

  let(:rules_data_response) do
    {
      'path' => 'datadog/603646/ASM_DD/latest/config',
      'raw' => Base64.strict_encode64(rules_data).chomp
    }
  end

  let(:blocked_ips_data_response) do
    {
      'path' => 'datadog/603646/ASM_DATA/blocked_ips/config',
      'raw' => Base64.strict_encode64(blocked_ips).chomp
    }
  end

  let(:exclusion_data_response) do
    {
      'path' => 'datadog/603646/ASM/exclusion_filters/config',
      'raw' => Base64.strict_encode64(exclusions).chomp
    }
  end

  let(:target_files) { [] }

  let(:client_configs) { [] }

  let(:response_body) do
    {
      'roots' => roots.map { |r| Base64.strict_encode64(r.to_json).chomp },
      'targets' => Base64.strict_encode64(targets.to_json).chomp,
      'target_files' => target_files,
      'client_configs' => client_configs,
    }.to_json
  end

  let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

  let(:capabilities) do
    capabilities = Datadog::Core::Remote::Client::Capabilities.new(Datadog::Core::Configuration::Settings.new)
    capabilities.send(:register_products, ['ASM_DATA', 'ASM_DD', 'ASM'])

    capabilities
  end

  subject(:client) { described_class.new(transport, capabilities, repository: repository) }

  describe '#sync' do
    include_context 'HTTP connection stub'

    let(:response_code) { 200 }

    let(:client_configs) do
      [
        'datadog/603646/ASM_DATA/blocked_ips/config',
        'datadog/603646/ASM_DD/latest/config',
        'datadog/603646/ASM/exclusion_filters/config'
      ]
    end

    let(:target_files) do
      [rules_data_response, blocked_ips_data_response, exclusion_data_response]
    end

    let(:target_content) do
      {}.merge(exclusions_filter_content).merge(blocked_ips_content).merge(rules_content)
    end

    context 'valid response' do
      include_context 'Client dispatches changes'

      it 'store all changes into the repository' do
        expect(repository.opaque_backend_state).to be_nil
        expect(repository.targets_version).to eq(0)
        expect(repository.contents.size).to eq(0)

        client.sync

        expect(repository.opaque_backend_state).to_not be_nil
        expect(repository.targets_version).to_not eq(0)
        expect(repository.contents.size).to_not eq(0)
      end

      it 'propagates changes to the dispatcher' do
        expect_any_instance_of(Datadog::Core::Remote::Dispatcher).to receive(:dispatch).with(
          instance_of(Datadog::Core::Remote::Configuration::Repository::ChangeSet), repository
        )
        client.sync
      end

      context 'when the data is the same' do
        it 'does not commit the information to the transaction' do
          expect_any_instance_of(Datadog::Core::Remote::Configuration::Repository::Transaction).to receive(:insert)
            .exactly(3).and_call_original
          client.sync
          client.sync
        end
      end

      context 'when the data has change' do
        it 'updates the contents' do
          client.sync

          # We have to modify the response to trick the client into think on the second sync
          # the content for datadog/603646/ASM_DATA/blocked_ips/config have change
          new_blocked_ips = '{"rules_data":[{"data":["fake new data"]}]}'
          expect_any_instance_of(Datadog::Core::Remote::Transport::HTTP::Config::Response)
            .to receive(:target_files)
            .and_return(
              [
                {
                  :path => 'datadog/603646/ASM_DATA/blocked_ips/config',
                  :content => StringIO.new(new_blocked_ips)
                },
                {
                  :path => 'datadog/603646/ASM/exclusion_filters/config',
                  :content => StringIO.new(exclusions)
                },
                {
                  :path => 'datadog/603646/ASM_DD/latest/config',
                  :content => StringIO.new(rules_data)
                }
              ]
            )

          updated_targets = {
            'signed' => {
              '_type' => 'targets',
              'custom' => {
                'agent_refresh_interval' => 50,
                'opaque_backend_state' => 'iucwgi'
              },
              'expires' => '2023-06-17T10:16:42Z',
              'spec_version' => '1.0.0',
              'targets' => {
                'datadog/603646/ASM/exclusion_filters/config' => {
                  'custom' => {
                    'c' => ['client_id'],
                    'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }] },
                    'v' => 21
                  },
                  'hashes' => { 'sha256' => Digest::SHA256.hexdigest(exclusions) },
                  'length' => 645
                },
                'datadog/603646/ASM_DATA/blocked_ips/config' => {
                  'custom' => {
                    'c' => ['client_id'],
                    'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }] },
                    'v' => 51
                  },
                  'hashes' => { 'sha256' => Digest::SHA256.hexdigest(new_blocked_ips) },
                  'length' => 1834
                },
                'datadog/603646/ASM_DD/latest/config' => {
                  'custom' => {
                    'c' => ['client_id'],
                    'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => 'client_id' }] },
                    'v' => 51
                  },
                  'hashes' => { 'sha256' => Digest::SHA256.hexdigest(rules_data) },
                  'length' => 1834
                }
              },
              'version' => 469154399387498379
            }
          }
          expect_any_instance_of(Datadog::Core::Remote::Transport::HTTP::Config::Response).to receive(:targets).and_return(
            updated_targets
          )

          expect_any_instance_of(Datadog::Core::Remote::Configuration::Repository::Transaction).to receive(:update)
            .exactly(1).and_call_original
          client.sync
        end
      end
    end

    context 'invalid response' do
      context 'invalid response body' do
        let(:response_body) do
          {
            'roots' => roots.map { |r| Base64.strict_encode64(r.to_json).chomp },
            'targets' => Base64.strict_encode64(targets.to_json).chomp,
            'target_files' => [
              {
                'path' => 'datadog/603646/ASM/exclusion_filters/config',
                'raw' => Base64.strict_encode64(exclusions).chomp
              }
            ],
            'client_configs' => [
              'datadog/603646/ASM_DATA/blocked_ips/config',
            ]
          }.to_json
        end

        context 'missing content for path from the response' do
          it 'raises SyncError' do
            expect do
              client.sync
            end.to raise_error(
              described_class::SyncError,
              %r{no valid content for target at path 'datadog/603646/ASM_DATA/blocked_ips/config'}
            )
          end
        end

        context 'missing target for path from the response' do
          let(:target_content) do
            {
              'datadog/603646/ASM/exclusion_filters/config' => {
                'custom' => {
                  'c' => ['client_id'],
                  'tracer-predicates' => {
                    'tracer_predicates_v1' => [
                      {
                        'clientID' => 'client_id'
                      }
                    ]
                  },
                  'v' => 21
                },
                'hashes' => { 'sha256' => Digest::SHA256.hexdigest(exclusions) },
                'length' => 645
              },
            }
          end

          it 'raises SyncError' do
            expect do
              client.sync
            end.to raise_error(
              described_class::SyncError,
              %r{no target for path 'datadog/603646/ASM_DATA/blocked_ips/config'}
            )
          end
        end

        context 'invalid path' do
          let(:target_content) do
            {
              'invalid path' => {
                'custom' => {
                  'c' => ['client_id'],
                  'tracer-predicates' => {
                    'tracer_predicates_v1' => [
                      { 'clientID' => 'client_id' }
                    ]
                  },
                  'v' => 21
                },
                'hashes' => { 'sha256' => 'fake sha' },
                'length' => 645
              },
            }
          end

          it 'raises SyncError' do
            expect { client.sync }.to raise_error(described_class::SyncError, /could not parse: "invalid path"/)
          end
        end
      end

      context 'with a network error' do
        it 'raises a transport error' do
          expect(http_connection).to receive(:request).and_raise(IOError)

          expect { client.sync }.to raise_error(Datadog::Core::Remote::Client::TransportError)
        end
      end
    end

    describe '#payload' do
      context 'no sync errors' do
        let(:response_code) { 200 }
        include_context 'Client dispatches changes'

        before { client.sync }

        context 'client' do
          let(:client_payload) { client.send(:payload)[:client] }

          context 'state' do
            it 'returns client state' do
              state = repository.state

              expected_state = {
                :root_version => state.root_version,
                :targets_version => state.targets_version,
                :config_states => state.config_states,
                :has_error => state.has_error,
                :error => state.error,
                :backend_client_state => state.opaque_backend_state
              }

              expect(client_payload[:state]).to eq(expected_state)
            end
          end

          context 'id' do
            it 'returns id' do
              expect(client_payload[:id]).to eq(client.instance_variable_get(:@id))
            end
          end

          context 'products' do
            it 'returns products' do
              expect(client_payload[:products]).to eq(capabilities.products)
            end
          end

          context 'capabilities' do
            it 'returns capabilities' do
              expect(client_payload[:capabilities]).to eq(capabilities.base64_capabilities)
            end
          end

          context 'is_tracer' do
            it 'returns true' do
              expect(client_payload[:is_tracer]).to eq(true)
            end
          end

          context 'is_agent' do
            it 'returns false' do
              expect(client_payload[:is_agent]).to eq(false)
            end
          end

          context 'client_tracer' do
            context 'tags' do
              let(:gem_datadog_version) { '1.1.1' }
              let(:ruby_platform) { 'ruby-platform' }
              let(:ruby_version) { '2.2.2' }
              let(:ruby_engine) { 'ruby_engine_name' }
              let(:ruby_engine_version) { '3.3.3' }
              let(:gem_platform_local) { 'gem-platform' }
              let(:native_platform) { 'native-platform' }
              let(:libddwaf_gem_spec) { Struct.new(:version, :platform).new('4.4.4', 'libddwaf-platform') }
              let(:libdatadog_gem_spec) { Struct.new(:version, :platform).new('5.5.5', 'libdatadog-platform') }

              before do
                stub_const('RUBY_PLATFORM', ruby_platform)
                stub_const('RUBY_VERSION', ruby_version)
                stub_const('RUBY_ENGINE', ruby_engine)
                stub_const('RUBY_ENGINE_VERSION', ruby_engine_version)

                allow(Gem::Platform).to receive(:local).and_return(gem_platform_local)
                allow(Datadog::Core::Environment::Identity).to receive(:gem_datadog_version).and_return(gem_datadog_version)
                allow(client).to receive(:ruby_engine_version).and_return(ruby_engine_version)
                allow(client).to receive(:native_platform).and_return(native_platform)
                allow(client).to receive(:gem_spec).with('libddwaf').and_return(libddwaf_gem_spec)
                allow(client).to receive(:gem_spec).with('libdatadog').and_return(libdatadog_gem_spec)
              end

              it 'returns client_tracer tags' do
                expect(Datadog.configuration).to receive(:version).and_return('hello').at_least(:once)

                expected_client_tracer_tags = [
                  "platform:#{native_platform}",
                  "ruby.tracer.version:#{gem_datadog_version}",
                  "ruby.runtime.platform:#{ruby_platform}",
                  "ruby.runtime.version:#{ruby_version}",
                  "ruby.runtime.engine.name:#{ruby_engine}",
                  "ruby.runtime.engine.version:#{ruby_engine_version}",
                  "ruby.rubygems.platform.local:#{gem_platform_local}",
                  "ruby.gem.libddwaf.version:#{libddwaf_gem_spec.version}",
                  "ruby.gem.libddwaf.platform:#{libddwaf_gem_spec.platform}",
                  "ruby.gem.libdatadog.version:#{libdatadog_gem_spec.version}",
                  "ruby.gem.libdatadog.platform:#{libdatadog_gem_spec.platform}",
                ]

                expect(client_payload[:client_tracer][:tags]).to eq(expected_client_tracer_tags)
              end
            end

            context 'with remote service setting' do
              it 'returns client_tracer' do
                expect(Datadog.configuration.remote).to receive(:service).and_return('foo').at_least(:once)

                expected_client_tracer = {
                  :runtime_id => Datadog::Core::Environment::Identity.id,
                  :language => Datadog::Core::Environment::Identity.lang,
                  :tracer_version => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
                  :service => Datadog.configuration.remote.service,
                  :env => Datadog.configuration.env,
                }

                expect(client_payload[:client_tracer].tap { |h| h.delete(:tags) }).to eq(expected_client_tracer)
              end
            end

            context 'with app_version' do
              it 'returns client_tracer' do
                expect(Datadog.configuration).to receive(:version).and_return('hello').at_least(:once)

                expected_client_tracer = {
                  :runtime_id => Datadog::Core::Environment::Identity.id,
                  :language => Datadog::Core::Environment::Identity.lang,
                  :tracer_version => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
                  :service => Datadog.configuration.service,
                  :env => Datadog.configuration.env,
                  :app_version => Datadog.configuration.version,
                }

                expect(client_payload[:client_tracer].tap { |h| h.delete(:tags) }).to eq(expected_client_tracer)
              end
            end

            context 'without app_version' do
              it 'returns client_tracer' do
                expect(Datadog.configuration).to receive(:version).and_return(nil).at_least(:once)

                expected_client_tracer = {
                  :runtime_id => Datadog::Core::Environment::Identity.id,
                  :language => Datadog::Core::Environment::Identity.lang,
                  :tracer_version => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
                  :service => Datadog.configuration.service,
                  :env => Datadog.configuration.env,
                }

                expect(client_payload[:client_tracer].tap { |h| h.delete(:tags) }).to eq(expected_client_tracer)
              end
            end
          end
        end

        context 'cached_target_files' do
          it 'returns cached_target_files' do
            state = repository.state

            expect(client.send(:payload)[:cached_target_files]).to eq(state.cached_target_files)
          end
        end
      end
    end
  end
end
