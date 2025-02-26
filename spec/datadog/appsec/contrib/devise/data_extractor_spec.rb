# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Contrib::Devise::DataExtractor do
  describe '#extract_id' do
    context 'when mode is set to identification' do
      let(:extractor) { described_class.new('identification') }

      it 'returns id from a hash containing id or uuid keys' do
        expect(extractor.extract_id(id: 1)).to eq('1')
        expect(extractor.extract_id('id' => 2)).to eq('2')
        expect(extractor.extract_id(uuid: 3)).to eq('3')
        expect(extractor.extract_id('uuid' => 4)).to eq('4')
      end

      it 'returns id from hash and gives priority to id over uuid' do
        expect(extractor.extract_id(uuid: 1, id: 2)).to eq('2')
        expect(extractor.extract_id('uuid' => 1, 'id' => 2)).to eq('2')
      end

      it 'returns id from hash with mixed key types and priorities' do
        expect(extractor.extract_id(uuid: 1, 'id' => 2)).to eq('2')
        expect(extractor.extract_id('uuid' => 1, id: 2)).to eq('2')
      end

      it 'returns nil if none of the possible keys are present' do
        expect(extractor.extract_id({})).to be_nil
      end

      it 'returns id from an object responding to id or uuid methods' do
        expect(extractor.extract_id(double('User', id: 1))).to eq('1')
        expect(extractor.extract_id(double('User', uuid: 2))).to eq('2')
      end

      it 'returns id from an object and gives priority to id over methods' do
        expect(extractor.extract_id(double('User', id: 1, uuid: 2))).to eq('1')
      end

      it 'return nil if object does not respond to id or uuid methods' do
        expect(extractor.extract_id(double('User'))).to be_nil
      end
    end

    context 'when mode is set to anonymization' do
      let(:extractor) { described_class.new('anonymization') }

      it 'returns anonymized id from a hash containing id or uuid keys' do
        expect(extractor.extract_id(id: 1)).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_id('id' => 2)).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_id(uuid: 3)).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_id('uuid' => 4)).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_id(uuid: 1, 'id' => 2)).to match(/anon_[a-z0-9]{32}/)
      end

      it 'returns nil if none of the possible keys are present' do
        expect(extractor.extract_id({})).to be_nil
      end
    end
  end

  describe '#extract_login' do
    context 'when mode is set to identification' do
      let(:extractor) { described_class.new('identification') }

      it 'returns login from a hash containing suitable keys' do
        expect(extractor.extract_login(email: 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login(login: 'example')).to eq('example')
        expect(extractor.extract_login(username: 'dotcom')).to eq('dotcom')
        expect(extractor.extract_login('email' => 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login('login' => 'example')).to eq('example')
        expect(extractor.extract_login('username' => 'dotcom')).to eq('dotcom')
      end

      it 'returns login from hash and gives priority to email over username and username over login' do
        expect(extractor.extract_login(username: 'dotcom', email: 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login(login: 'example', email: 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login(login: 'example', username: 'dotcom', email: 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login(username: 'example', login: 'ex@mple.com')).to eq('example')

        expect(extractor.extract_login('username' => 'dotcom', 'email' => 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login('login' => 'example', 'email' => 'ex@mple.com')).to eq('ex@mple.com')
        expect(extractor.extract_login('login' => 'example', 'username' => 'dotcom', 'email' => 'ex@mple.com'))
          .to eq('ex@mple.com')
        expect(extractor.extract_login('username' => 'example', 'login' => 'ex@mple.com')).to eq('example')
      end

      it 'returns login from hash with mixed key types and priorities' do
        expect(extractor.extract_login('username' => 'example', login: 'ex@mple.com')).to eq('example')
        expect(extractor.extract_login(login: 'example', username: 'dotcom', 'email' => 'ex@mple.com'))
          .to eq('ex@mple.com')
      end

      it 'returns nil if none of the possible keys are present' do
        expect(extractor.extract_login({})).to be_nil
      end

      it 'returns login from an object responding to suitable methods' do
        expect(extractor.extract_login(double('User', email: 'ex@mple.com'))).to eq('ex@mple.com')
        expect(extractor.extract_login(double('User', username: 'example'))).to eq('example')
        expect(extractor.extract_login(double('User', login: 'dotcom'))).to eq('dotcom')
      end

      it 'returns login from an object and gives priority to email over username and username over login' do
        expect(extractor.extract_login(double('User', username: 'dotcom', email: 'ex@mple.com'))).to eq('ex@mple.com')
        expect(extractor.extract_login(double('User', login: 'dotcom', email: 'ex@mple.com'))).to eq('ex@mple.com')
        expect(extractor.extract_login(double('User', username: 'example', login: 'dotcom', email: 'ex@mple.com')))
          .to eq('ex@mple.com')
        expect(extractor.extract_login(double('User', login: 'dotcom', username: 'example'))).to eq('example')
      end

      it 'return nil if object does not respond to email or other methods' do
        expect(extractor.extract_login(double('User'))).to be_nil
      end
    end

    context 'when mode is set to anonymization' do
      let(:extractor) { described_class.new('anonymization') }

      it 'returns anonymized login from a hash containing one of the keys' do
        expect(extractor.extract_login(email: 'ex@mple.com')).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_login(login: 'example')).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_login('username' => 'dotcom')).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_login(login: 'example', 'email' => 'ex@mple.com')).to match(/anon_[a-z0-9]{32}/)
      end

      it 'returns anonymized login from an object responding to one of the methods' do
        expect(extractor.extract_login(double('User', email: 'ex@mple.com'))).to match(/anon_[a-z0-9]{32}/)
        expect(extractor.extract_login(double('User', username: 'dotcom'))).to match(/anon_[a-z0-9]{32}/)
      end

      it 'returns nil if none of the possible keys are present' do
        expect(extractor.extract_login({})).to be_nil
      end

      it 'return nil if object does not respond to id or uuid methods' do
        expect(extractor.extract_id(double('User'))).to be_nil
      end
    end
  end
end
