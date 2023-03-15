require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor/rule_merger'

RSpec.describe Datadog::AppSec::Processor::RuleMerger do
  let(:rules) do
    [
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
      }.freeze
    ].freeze
  end

  context 'rules' do
    context 'multiple rules files' do
      context 'version' do
        it 'merge rules files when the version is the same' do
          rules_dup = rules.dup
          rules_dup[1] = {
            'version' => '2.2',
            'metadata' => {
              'rules_version' => '1.4.3'
            },
            'rules' => [
              {
                'id' => 'crs-942-100',
                'name' => 'SQL Injection Attack Detected via libinjection',
                'tags' => {
                  'type' => 'sql_injection',
                  'crs_id' => '942100',
                  'category' => 'attack_attempt'
                },
                'conditions' => [
                  {
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'server.request.query'
                        },
                        {
                          'address' => 'server.request.body'
                        },
                        {
                          'address' => 'server.request.path_params'
                        },
                        {
                          'address' => 'grpc.server.request.message'
                        }
                      ]
                    },
                    'operator' => 'is_sqli'
                  }
                ],
                'transformers' => [
                  'removeNulls'
                ],
                'on_match' => [
                  'block'
                ]
              },
            ]
          }.freeze

          expected_result = {
            'version' => '2.2',
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
              },
              {
                'id' => 'crs-942-100',
                'name' => 'SQL Injection Attack Detected via libinjection',
                'tags' => {
                  'type' => 'sql_injection',
                  'crs_id' => '942100',
                  'category' => 'attack_attempt'
                },
                'conditions' => [
                  {
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'server.request.query'
                        },
                        {
                          'address' => 'server.request.body'
                        },
                        {
                          'address' => 'server.request.path_params'
                        },
                        {
                          'address' => 'grpc.server.request.message'
                        }
                      ]
                    },
                    'operator' => 'is_sqli'
                  }
                ],
                'transformers' => [
                  'removeNulls'
                ],
                'on_match' => [
                  'block'
                ]
              },
            ]
          }

          result = described_class.merge(rules: rules_dup.freeze)
          expect(result).to eq(expected_result)
        end

        it 'raises RuleVersionMismatchError is the rules version is not the same' do
          rules_dup = rules.dup
          rules_dup[1] = {
            'version' => '2.3',
            'metadata' => {
              'rules_version' => '1.4.3'
            },
            'rules' => [
              {
                'id' => 'crs-942-100',
                'name' => 'SQL Injection Attack Detected via libinjection',
                'tags' => {
                  'type' => 'sql_injection',
                  'crs_id' => '942100',
                  'category' => 'attack_attempt'
                },
                'conditions' => [
                  {
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'server.request.query'
                        },
                        {
                          'address' => 'server.request.body'
                        },
                        {
                          'address' => 'server.request.path_params'
                        },
                        {
                          'address' => 'grpc.server.request.message'
                        }
                      ]
                    },
                    'operator' => 'is_sqli'
                  }
                ],
                'transformers' => [
                  'removeNulls'
                ],
                'on_match' => [
                  'block'
                ]
              },
            ]
          }.freeze

          expect do
            described_class.merge(rules: rules_dup.freeze)
          end.to raise_error(described_class::RuleVersionMismatchError)
        end
      end
    end
  end

  context 'overrides' do
    context 'without overrides' do
      it 'does not merge rules_overrides or exclusions' do
        expected_result = rules[0]

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

        expected_result = rules[0].merge(
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
    end
  end

  context 'exclusions' do
    it 'merges exclusions' do
      exclusions = [
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
                    'regex' => '^/api/v2/source-code-integration/enrich-stack-trace'
                  }
                }
              ],
              'id' => 'f40fbf52-baec-42bd-9868-cf002b6cdbed',
              'inputs' => [
                {
                  'address' => 'server.request.query',
                  'key_path' => [
                    'stack'
                  ]
                },
                {
                  'address' => 'server.request.body',
                  'key_path' => [
                    'stack'
                  ]
                },
                {
                  'address' => 'server.request.path_params',
                  'key_path' => [
                    'stack'
                  ]
                }
              ]
            }
          ],
        }
      ]

      expected_result = rules[0].merge(
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
            },
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
                    'regex' => '^/api/v2/source-code-integration/enrich-stack-trace'
                  }
                }
              ],
              'id' => 'f40fbf52-baec-42bd-9868-cf002b6cdbed',
              'inputs' => [
                {
                  'address' => 'server.request.query',
                  'key_path' => [
                    'stack'
                  ]
                },
                {
                  'address' => 'server.request.body',
                  'key_path' => [
                    'stack'
                  ]
                },
                {
                  'address' => 'server.request.path_params',
                  'key_path' => [
                    'stack'
                  ]
                }
              ]
            }
          ]
        }
      )

      result = described_class.merge(rules: rules, exclusions: exclusions)
      expect(result).to eq(expected_result)
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

      expected_result = rules[0].merge(
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

      expected_result = rules[0].merge(
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

        expected_result = rules[0].merge(
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

      it 'removes expiration key if no experation is provided' do
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

        expected_result = rules[0].merge(
          {
            'rules_data' => [
              {
                'id' => 'blocked_users',
                'type' => 'data_with_expiration',
                'data' => [
                  {
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

    context 'data, overrides, and exclusions' do
      it 'merges all information' do
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

        exclusions = [
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
          },
        ]

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

        expected_result = rules[0].merge(
          {
            'rules_data' => [
              {
                'id' => 'blocked_users',
                'type' => 'data_with_expiration',
                'data' => [
                  {
                    'value' => 'this is a test'
                  }
                ]
              }
            ],
            'rules_override' => [
              {
                'id' => 'usr-001-001',
                'on_match' => ['block']
              },
              {
                'enabled' => false,
                'id' => 'usr-001-001'
              }
            ],
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
        )

        result = described_class.merge(rules: rules, data: rules_data, overrides: rules_overrides, exclusions: exclusions)
        expect(result).to eq(expected_result)
      end
    end
  end
end
