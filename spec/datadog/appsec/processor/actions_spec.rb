require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor/actions'

RSpec.describe Datadog::AppSec::Processor::Actions do
  after do
    described_class.send(:reset)
  end

  let(:actions) do
    [
      {
        'id' => 'block',
        'parameters' => {
          'type' => 'auto',
          'status_code' => 403,

        }
      }
    ]
  end

  describe '.merge' do
    context 'empty actions' do
      it 'stores the actions' do
        described_class.merge(actions)
        expect(described_class.actions).to eq(actions)
      end
    end

    context 'no empty actions' do
      it 'merges' do
        described_class.merge(actions)
        expect(described_class.actions).to eq(actions)

        actions_to_merge = [
          {
            'id' => 'redirect_request',
            'parameters' => {
              'location' => 'foo',
              'status_code' => 303,

            }
          }
        ]

        expectd_result = []
        expectd_result.concat(actions)
        expectd_result.concat(actions_to_merge)

        described_class.merge(actions_to_merge)

        expect(described_class.actions).to match_array(expectd_result)
      end

      it 'merges and updates exiting ones' do
        described_class.merge(actions)
        expect(described_class.actions).to eq(actions)

        actions_to_merge = [
          {
            'id' => 'block',
            'parameters' => {
              'type' => 'html',
              'status_code' => 403,

            }
          },
          {
            'id' => 'redirect_request',
            'parameters' => {
              'location' => 'foo',
              'status_code' => 303,

            }
          }
        ]

        described_class.merge(actions_to_merge)
        expect(described_class.actions).to eq(actions_to_merge)
      end
    end
  end

  describe '.fetch_configuration' do
    it 'returns the existing configuration' do
      described_class.merge(actions)
      expect(described_class.fetch_configuration('block')).to eq(
        {
          'id' => 'block',
          'parameters' => {
            'type' => 'auto',
            'status_code' => 403,

          }
        }
      )
    end

    it 'returns nil if no configuration matches' do
      described_class.merge(actions)
      expect(described_class.fetch_configuration('fake')).to be_nil
    end
  end
end
