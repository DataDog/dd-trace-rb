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

    context 'with invalid characters in operation name' do
      let(:input) { 'Get-Ad:bad,ListIp:geo' }

      it 'skips invalid operation names' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('Get-Ad', 'bad')).to be false
      end
    end

    context 'with invalid characters in variable name' do
      let(:input) { 'GetAd:in-valid,ListIp:geo' }

      it 'skips invalid variable names' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('GetAd', 'in-valid')).to be false
      end
    end

    context 'with whitespace around colon' do
      let(:input) { 'GetAd : bad,ListIp:geo' }

      it 'treats whitespace as invalid' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('GetAd ', 'bad')).to be false
      end
    end

    context 'with missing colon' do
      let(:input) { 'GetAd,ListIp:geo' }

      it 'skips fragments without colon' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('GetAd', '')).to be false
      end
    end

    context 'with empty operation name' do
      let(:input) { ':id,ListIp:geo' }

      it 'skips empty operation names' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('', 'id')).to be false
      end
    end

    context 'with empty variable name' do
      let(:input) { 'GetAd:,ListIp:geo' }

      it 'skips empty variable names' do
        expect(config.match?('ListIp', 'geo')).to be true
        expect(config.match?('GetAd', '')).to be false
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
      it 'returns false for GetUser:title' do
        expect(config.match?('GetUser', 'title')).to be false
      end

      it 'returns false for GetPost:id' do
        expect(config.match?('GetPost', 'id')).to be false
      end

      it 'returns false for UnknownOperation:id' do
        expect(config.match?('UnknownOperation', 'id')).to be false
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
