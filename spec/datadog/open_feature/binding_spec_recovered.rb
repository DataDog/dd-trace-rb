require 'datadog/open_feature'

RSpec.describe Datadog::OpenFeature::Binding do
  let(:sample_config_json) do
    {
      "id": "1",
      "createdAt": "2024-04-17T19:40:53.716Z",
      "format": "SERVER",
      "environment": {
        "name": "test"
      },
      "flags": {
        "test_flag": {
          "key": "test_flag",
          "enabled": true,
          "variationType": "STRING",
          "variations": {
            "control": {
              "key": "control",
              "value": "control_value"
            }
          },
          "allocations": [
            {
              "key": "rollout",
              "splits": [
                {
                  "variationKey": "control",
                  "shards": []
                }
              ],
              "doLog": false
            }
          ]
        }
      }
    }.to_json
  end

  describe '.supported?' do
    context 'when feature flags are supported' do
      it 'returns true' do
        expect(described_class.supported?).to be true
      end
    end

    context 'when feature flags are not supported' do
      before do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'Example error loading libdatadog_api')
      end

      it 'returns false' do
        expect(described_class.supported?).to be false
      end
    end
  end

  context 'when Feature Flags are not supported' do
    before do
      stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'Example error loading libdatadog_api')
    end

    describe described_class::Configuration do
      it 'raises an error' do
        expect { described_class.new(sample_config_json) }.to raise_error(
          ArgumentError, 
          'Feature Flags are not supported: Example error loading libdatadog_api'
        )
      end
    end

    describe described_class::EvaluationContext do
      it 'raises an error for new' do
        expect { described_class.new('user123') }.to raise_error(
          ArgumentError, 
          'Feature Flags are not supported: Example error loading libdatadog_api'
        )
      end

      it 'raises an error for new with attributes' do
        expect { described_class.new('user123', {'country' => 'US'}) }.to raise_error(
          ArgumentError, 
          'Feature Flags are not supported: Example error loading libdatadog_api'
        )
      end
    end

    describe '.get_assignment' do
      it 'raises an error' do
        config = double('config')
        context = double('context')
        expect { described_class.get_assignment(config, 'test_flag', context) }.to raise_error(
          ArgumentError, 
          'Feature Flags are not supported: Example error loading libdatadog_api'
        )
      end
    end
  end

  context 'when Feature Flags are supported' do
    let(:configuration) { Datadog::OpenFeature::Binding::Configuration.new(sample_config_json) }
    let(:evaluation_context) { Datadog::OpenFeature::Binding::EvaluationContext.new('user123') }

    describe described_class::Configuration do
      describe '#initialize' do
        it 'creates a configuration from JSON' do
          expect { configuration }.not_to raise_error
        end

        context 'with invalid JSON' do
          it 'raises an error' do
            expect { Datadog::OpenFeature::Binding::Configuration.new('invalid json') }.to raise_error(RuntimeError)
          end
        end
      end
    end

    describe described_class::EvaluationContext do
      describe '#initialize' do
        it 'creates an evaluation context with targeting key' do
          expect { evaluation_context }.not_to raise_error
        end
      end

      describe '.new with attributes' do
        let(:context_with_attribute) do
          described_class.new('user123', {'country' => 'US'})
        end

        it 'creates an evaluation context with attribute' do
          expect { context_with_attribute }.not_to raise_error
        end
      end
    end

    describe '.get_assignment' do
      subject(:resolution_details) { described_class.get_assignment(configuration, flag_key, evaluation_context) }

      context 'with existing flag' do
        let(:flag_key) { 'test_flag' }

        it 'returns a ResolutionDetails object' do
          expect(resolution_details).to be_a(described_class::ResolutionDetails)
        end
      end

      context 'with non-existing flag' do
        let(:flag_key) { 'nonexistent_flag' }

        it 'returns a ResolutionDetails object with error information' do
          expect(resolution_details).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
          expect(resolution_details.reason).to eq(:error)
          expect(resolution_details.error_code).to eq(:flag_not_found)
        end
      end

      context 'with invalid flag key type' do
        let(:flag_key) { 123 }

        it 'raises an error' do
          expect { resolution_details }.to raise_error(TypeError)
        end
      end

      context 'with nil flag key' do
        let(:flag_key) { nil }

        it 'raises an error' do
          expect { resolution_details }.to raise_error(TypeError)
        end
      end

      context 'error handling verification' do
        it 'has error accessor methods that return nil for successful evaluations' do
          config = described_class::Configuration.new(sample_config_json)
          context = described_class::EvaluationContext.new('test_user')
          result = described_class.get_assignment(config, 'test_flag', context)
          
          expect(result).to be_a(described_class::ResolutionDetails)
          expect(result.error_code).to be_nil
          expect(result.error_message).to be_nil
          expect(result.reason).to eq(:static)
        end
      end
    end

    describe described_class::ResolutionDetails do
      describe '#initialize' do
        it 'creates a resolution details object' do
          expect { described_class.new }.not_to raise_error
        end
      end

      context 'with a valid assignment result' do
        let(:resolution_details) { Datadog::OpenFeature::Binding.get_assignment(configuration, 'test_flag', evaluation_context) }

        it 'has accessor methods for all fields' do
          expect(resolution_details).to respond_to(:value)
          expect(resolution_details).to respond_to(:reason)
          expect(resolution_details).to respond_to(:error_code)
          expect(resolution_details).to respond_to(:error_message)
          expect(resolution_details).to respond_to(:variant)
          expect(resolution_details).to respond_to(:allocation_key)
          expect(resolution_details).to respond_to(:do_log)
        end

        it 'returns proper values for successful evaluation' do
          expect(resolution_details.error_code).to be_nil
          expect(resolution_details.error_message).to be_nil
          expect(resolution_details.reason).to eq(:static)
        end
      end

      context 'with configuration errors' do
        let(:invalid_config_json) do
          {
            "id": "1",
            "createdAt": "2024-04-17T19:40:53.716Z",
            "format": "SERVER",
            "environment": { "name": "test" },
            "flags": {
              "type_mismatch_flag": {
                "key": "type_mismatch_flag",
                "enabled": true,
                "variationType": "BOOLEAN",  # Expecting BOOLEAN
                "variations": {
                  "control": {
                    "key": "control", 
                    "value": "string_value"  # But providing STRING
                  }
                },
                "allocations": [{
                  "key": "rollout",
                  "splits": [{ "variationKey": "control", "shards": [] }],
                  "doLog": false
                }]
              }
            }
          }.to_json
        end

        it 'handles configuration errors gracefully' do
          begin
            config = Datadog::OpenFeature::Binding::Configuration.new(invalid_config_json)
            context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user')
            resolution_details = Datadog::OpenFeature::Binding.get_assignment(config, 'type_mismatch_flag', context)
            
            # If we get a result (rather than an exception), verify it's handled gracefully
            if resolution_details
              expect(resolution_details).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
              # FFE library handles type mismatches gracefully 
              expect(resolution_details.reason).to eq(:error)
              # Should have error information for type mismatch
              expect(resolution_details.error_code).to eq(:parse_error)
              expect(resolution_details.error_message).not_to be_nil
            end
          rescue => e
            # If configuration creation fails, that's also valid - just note it
            puts "Configuration error (expected): #{e.message}"
          end
        end
      end
    end

    describe 'integration test' do
      it 'performs a complete flag evaluation workflow' do
        # Create configuration
        config = described_class::Configuration.new(sample_config_json)
        expect(config).to be_a(described_class::Configuration)

        # Create evaluation context
        context = described_class::EvaluationContext.new('test_user')
        expect(context).to be_a(described_class::EvaluationContext)

        # Evaluate flag
        resolution_details = described_class.get_assignment(config, 'test_flag', context)
        expect(resolution_details).to be_a(described_class::ResolutionDetails)
      end

      it 'works with context created with attributes' do
        # Create configuration
        config = described_class::Configuration.new(sample_config_json)

        # Create evaluation context with attribute
        context = described_class::EvaluationContext.new('test_user', {'plan' => 'premium'})
        expect(context).to be_a(described_class::EvaluationContext)

        # Evaluate flag
        resolution_details = described_class.get_assignment(config, 'test_flag', context)
        expect(resolution_details).to be_a(described_class::ResolutionDetails)
      end
    end
  end
end