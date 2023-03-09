require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor/rule_merger'

RSpec.describe Datadog::AppSec::Processor::RuleMerger do
  let(:rules) do
    {
      'version' => '2.2',
      'metadata' => {
        'rules_version' => '1.4.3'
      },
      'rules' => [
        {
          'id' => 'usr-001-001',
          'name' => 'Super rule',
          'tags' => {
            'type' => 'security_scanner',
            'category' => 'scanners'
          },
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^SuperScanner$'
              },
              'operator' => 'regex_match'
            }
          ],
          'transformers' => []
        }
      ]
    }
  end

  context 'overrides' do
    context 'without overrides' do
      it 'does not merge rules_overrides or exclusions' do
        expected_result = rules

        result = described_class.merge(rules: rules)
        expect(result).to eq(expected_result)
      end
    end

    context 'with overrides' do
      it 'merge rules_overrides' do
        rules_overrides = [
          {
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'on_match' => ['block']
              }
            ]
          },
          {
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'enabled' => false,
              }
            ]
          },
        ]

        expected_result = rules.merge(
          {
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'on_match' => ['block']
              },
              {
                'id' => 'usr-001-001',
                'enabled' => false
              }
            ]
          }
        )

        result = described_class.merge(rules: rules, overrides: rules_overrides)
        expect(result).to eq(expected_result)
      end

      it 'merges exclusions' do
        rules_overrides = [
          {
            'exclusions' => [
              {
                'conditions' => [
                  {
                    'operator' => 'match_regex',
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'server.request.uri.raw'
                        }
                      ],
                      'options' => {
                        'case_sensitive' => false
                      },
                      'regex' => '^/api/v2/ci/pipeline/.*'
                    }
                  }
                ],
                'id' => '1931d0f4-c521-4500-af34-6c4d8b8b3494'
              }
            ]
          }
        ]

        expected_result = rules.merge(
          {
            'exclusions' => [
              {
                'conditions' => [
                  {
                    'operator' => 'match_regex',
                    'parameters' => {
                      'inputs' => [
                        { 'address' => 'server.request.uri.raw' }
                      ],
                      'options' => { 'case_sensitive' => false },
                      'regex' => '^/api/v2/ci/pipeline/.*'
                    }
                  }
                ],
                'id' => '1931d0f4-c521-4500-af34-6c4d8b8b3494'
              }
            ]
          }
        )

        result = described_class.merge(rules: rules, overrides: rules_overrides)
        expect(result).to eq(expected_result)
      end

      it 'merges rules_overrides and exclusions' do
        rules_overrides = [
          {
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'on_match' => ['block']
              }
            ]
          },
          {
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'enabled' => false,
              }
            ]
          },
          {
            'exclusions' => [
              {
                'conditions' => [
                  {
                    'operator' => 'match_regex',
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'server.request.uri.raw'
                        }
                      ],
                      'options' => {
                        'case_sensitive' => false
                      },
                      'regex' => '^/api/v2/ci/pipeline/.*'
                    }
                  }
                ],
                'id' => '1931d0f4-c521-4500-af34-6c4d8b8b3494'
              }
            ]
          }
        ]

        expected_result = rules.merge(
          {
            'exclusions' => [
              {
                'conditions' => [
                  {
                    'operator' => 'match_regex',
                    'parameters' => {
                      'inputs' => [
                        { 'address' => 'server.request.uri.raw' }
                      ],
                      'options' => { 'case_sensitive' => false },
                      'regex' => '^/api/v2/ci/pipeline/.*'
                    }
                  }
                ],
                'id' => '1931d0f4-c521-4500-af34-6c4d8b8b3494'
              }
            ],
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'on_match' => ['block']
              },
              {
                'id' => 'usr-001-001',
                'enabled' => false
              }
            ]
          }
        )

        result = described_class.merge(rules: rules, overrides: rules_overrides)
        expect(result).to eq(expected_result)
      end
    end
  end

  context 'data' do
    it 'merges rules_data' do
      rules_data = [
        {
          'rules_data' => [
            {
              'data' => [
                {
                  'expiration' => 1677171437,
                  'value' => 'this is a test'
                }
              ],
              'id' => 'blocked_users',
              'type' => 'data_with_expiration'
            }
          ]
        },
        {
          'rules_data' => [
            {
              'data' => [
                {
                  'expiration' => 1678279317,
                  'value' => '9.9.9.9'
                }
              ],
              'id' => 'blocked_ips',
              'type' => 'ip_with_expiration'
            }
          ]
        },
        {
          'rules_data' => [
            {
              'data' => [
                {
                  'expiration' => 1678279317,
                  'value' => 'this is a second test'
                }
              ],
              'id' => 'blocked_users',
              'type' => 'data_with_expiration'
            }
          ]
        }
      ]

      expected_result = rules.merge(
        {
          'rules_data' => [
            {
              'id' => 'blocked_users',
              'type' => 'data_with_expiration',
              'data' => [
                {
                  'expiration' => 1677171437,
                  'value' => 'this is a test'
                },
                {
                  'expiration' => 1678279317,
                  'value' => 'this is a second test'
                }
              ]
            },
            {
              'id' => 'blocked_ips',
              'type' => 'ip_with_expiration',
              'data' => [
                {
                  'expiration' => 1678279317,
                  'value' => '9.9.9.9'
                }
              ]
            },
          ]
        }
      )

      result = described_class.merge(rules: rules, data: rules_data)
      expect(result).to eq(expected_result)
    end

    it 'merges data of different types' do
      rules_data = [
        {
          'rules_data' => [
            {
              'data' => [
                {
                  'expiration' => 1677171437,
                  'value' => 'this is a test'
                }
              ],
              'id' => 'blocked_users',
              'type' => 'data_with_expiration'
            }
          ]
        },
        {
          'rules_data' => [
            {
              'data' => [
                {
                  'value' => 'this is a test'
                }
              ],
              'id' => 'blocked_users',
              'type' => 'test_data'
            }
          ]
        }
      ]

      expected_result = rules.merge(
        {
          'rules_data' => [
            {
              'id' => 'blocked_users',
              'type' => 'data_with_expiration',
              'data' => [
                {
                  'expiration' => 1677171437,
                  'value' => 'this is a test'
                }
              ]
            },
            {
              'data' => [
                {
                  'value' => 'this is a test'
                }
              ],
              'id' => 'blocked_users',
              'type' => 'test_data'
            }
          ]
        }
      )

      result = described_class.merge(rules: rules, data: rules_data)
      expect(result).to eq(expected_result)
    end

    context 'with duplicates entries' do
      it 'removes duplicate entry and leave the one with the longest expiration ' do
        rules_data = [
          {
            'rules_data' => [
              {
                'data' => [
                  {
                    'expiration' => 1677171437,
                    'value' => 'this is a test'
                  }
                ],
                'id' => 'blocked_users',
                'type' => 'data_with_expiration'
              }
            ]
          },
          {
            'rules_data' => [
              {
                'data' => [
                  {
                    'expiration' => 167710000,
                    'value' => 'this is a test'
                  }
                ],
                'id' => 'blocked_users',
                'type' => 'data_with_expiration'
              }
            ]
          }
        ]

        expected_result = rules.merge(
          {
            'rules_data' => [
              {
                'id' => 'blocked_users',
                'type' => 'data_with_expiration',
                'data' => [
                  {
                    'expiration' => 1677171437,
                    'value' => 'this is a test'
                  }
                ]
              }
            ]
          }
        )

        result = described_class.merge(rules: rules, data: rules_data)
        expect(result).to eq(expected_result)
      end

      it 'keeps the entry without expiration' do
        rules_data = [
          {
            'rules_data' => [
              {
                'data' => [
                  {
                    'expiration' => 1677171437,
                    'value' => 'this is a test'
                  }
                ],
                'id' => 'blocked_users',
                'type' => 'data_with_expiration'
              }
            ]
          },
          {
            'rules_data' => [
              {
                'data' => [
                  {
                    'value' => 'this is a test'
                  }
                ],
                'id' => 'blocked_users',
                'type' => 'data_with_expiration'
              }
            ]
          }
        ]

        expected_result = rules.merge(
          {
            'rules_data' => [
              {
                'id' => 'blocked_users',
                'type' => 'data_with_expiration',
                'data' => [
                  {
                    'expiration' => 0,
                    'value' => 'this is a test'
                  }
                ]
              }
            ]
          }
        )

        result = described_class.merge(rules: rules, data: rules_data)
        expect(result).to eq(expected_result)
      end
    end
  end
end
