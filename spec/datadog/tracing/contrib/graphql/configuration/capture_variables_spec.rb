# frozen_string_literal: true

require 'datadog/tracing/contrib/graphql/configuration/capture_variables'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Configuration::CaptureVariables do
  describe '.new' do
    subject(:config) { described_class.new(input) }

    context 'with empty array input' do
      let(:input) { [] }

      it { expect(config.empty?).to be true }
    end

    context 'with empty string' do
      let(:input) { '' }

      it { expect(config.empty?).to be true }
    end

    context 'with valid fragments' do
      let(:input) { 'GetAd:id,ListIp:geo,AddKey:val' }

      it 'correctly parses operation and variable configuration' do
        expect(config.match?('GetAd', 'id')).to be true
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('AddKey', 'val')).to be true
        expect(config.match?('GetAd', 'geo')).to be false
      end

      it { expect(config.empty?).to be false }
    end

    context 'with array input' do
      let(:input) { ['GetAd:id', 'ListIp:geo', 'AddKey:val'] }

      it 'correctly parses operation and variable configuration' do
        expect(config.match?('GetAd', 'id')).to be true
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('AddKey', 'val')).to be true
        expect(config.match?('GetAd', 'geo')).to be false
      end

      it 'converts array to comma-separated string for to_s' do
        expect(config.to_s).to eq('GetAd:id,ListIp:geo,AddKey:val')
      end

      it { expect(config.empty?).to be false }
    end

    context 'with duplicate operation:variable pairs' do
      let(:input) { 'GetAd:id,GetAd:id,ListIp:geo' }

      it 'deduplicates entries' do
        expect(config.match?('GetAd', 'id')).to be true
        expect(config.match?('ListIp', 'geo')).to be true
      end
    end

    context 'with multiple variables for same operation' do
      let(:input) { 'GetUser:id,GetUser:name,GetUser:email' }

      it 'groups variables under same operation' do
        expect(config.match?('GetUser', 'id')).to be true
        expect(config.match?('GetUser', 'name')).to be true
        expect(config.match?('GetUser', 'email')).to be true
        expect(config.match?('GetUser', 'other')).to be false
      end
    end

    context 'with same variable used by multiple operations' do
      let(:input) { 'GetUser:id,GetPost:id,GetComment:id' }

      it 'handles same variable used by multiple operations' do
        expect(config.match?('GetUser', 'id')).to be true
        expect(config.match?('GetPost', 'id')).to be true
        expect(config.match?('GetComment', 'id')).to be true
        expect(config.match?('GetUser', 'name')).to be false
      end
    end

    context 'with whitespace around fragments' do
      let(:input) { ' GetAd:id  , ListIp:geo  ' }

      it 'handles whitespace correctly' do
        expect(config.match?('GetAd', 'id')).to be true
        expect(config.match?('ListIp', 'geo')).to be true
      end
    end

    context 'with empty fragments' do
      let(:input) { ',,GetAd:id,' }

      it 'skips empty fragments' do
        expect(config.match?('GetAd', 'id')).to be true
      end
    end

    context 'with invalid configurations' do
      let(:valid_fragment) { 'ListIp:geo' }

      [
        { input: 'Get-Ad:bad,ListIp:geo', desc: 'invalid characters in operation name', invalid: ['Get-Ad', 'bad'] },
        { input: 'GetAd:in-valid,ListIp:geo', desc: 'invalid characters in variable name', invalid: ['GetAd', 'in-valid'] },
        { input: 'GetAd : bad,ListIp:geo', desc: 'whitespace around colon', invalid: ['GetAd ', 'bad'] },
        { input: 'GetAd,ListIp:geo', desc: 'missing colon', invalid: ['GetAd', ''] },
        { input: ':id,ListIp:geo', desc: 'empty operation name', invalid: ['', 'id'] },
        { input: 'GetAd:,ListIp:geo', desc: 'empty variable name', invalid: ['GetAd', ''] }
      ].each do |test_case|
        context "with #{test_case[:desc]}" do
          let(:input) { test_case[:input] }

          it 'skips invalid fragments but keeps valid ones' do
            expect(config.match?('ListIp', 'geo')).to be true
            expect(config.match?(test_case[:invalid][0], test_case[:invalid][1])).to be false
          end
        end
      end
    end

    context 'with valid alphanumeric and underscore names' do
      let(:input) { 'Get_Ad:var_1,Load_Ip:key_2' }

      it 'accepts valid names with underscores and numbers' do
        expect(config.match?('Get_Ad', 'var_1')).to be true
        expect(config.match?('Load_Ip', 'key_2')).to be true
      end
    end

    context 'with multiple colons' do
      let(:input) { 'GetAd:id:bad,ListIp:geo' }

      it 'skips fragments with multiple colons' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('GetAd', 'id:bad')).to be false
      end
    end
  end

  describe '#match?' do
    subject(:config) { described_class.new('GetUser:id,GetUser:name,GetPost:title') }

    context 'with configured operation and variable' do
      it 'returns true for GetUser:id' do
        expect(config.match?('GetUser', 'id')).to be true
      end

      it 'returns true for GetUser:name' do
        expect(config.match?('GetUser', 'name')).to be true
      end

      it 'returns true for GetPost:title' do
        expect(config.match?('GetPost', 'title')).to be true
      end
    end

    context 'with unconfigured combinations' do
      [
        ['GetUser', 'title'],
        ['GetPost', 'id'],
        ['UnknownOperation', 'id']
      ].each do |operation, variable|
        it "returns false for #{operation}:#{variable}" do
          expect(config.match?(operation, variable)).to be false
        end
      end
    end
  end

  describe '#to_s' do
    subject(:config) { described_class.new('GetUser:id,GetUser:name') }

    it 'returns the original configuration string' do
      expect(config.to_s).to eq('GetUser:id,GetUser:name')
    end
  end

  describe '#empty?' do
    context 'with no configuration' do
      subject(:config) { described_class.new([]) }

      it { is_expected.to be_empty }
    end

    context 'with configuration' do
      subject(:config) { described_class.new('GetUser:id') }

      it { is_expected.not_to be_empty }
    end
  end
end
