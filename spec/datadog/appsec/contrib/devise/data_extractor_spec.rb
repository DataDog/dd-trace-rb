# frozen_string_literal: true

require 'devise'
require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Contrib::Devise::DataExtractor do
  before { allow(Devise).to receive(:mappings).and_return(mappings) }

  let(:mappings) do
    { user: instance_double(Devise::Mapping, name: :user, class_name: 'User') }
  end

  describe '#extract_id' do
    context 'when there is more that single user model' do
      let(:extractor) { described_class.new(mode: 'identification') }
      let(:mappings) do
        {
          user: instance_double(Devise::Mapping, name: :user, class_name: 'User'),
          admin: instance_double(Devise::Mapping, name: :admin, class_name: 'Admin')
        }
      end

      it 'returns prefixed id for matching mapping' do
        user = double(id: 1, class: double(name: 'User'))
        admin = double(id: 1, class: double(name: 'Admin'))

        expect(extractor.extract_id(user)).to eq('user:1')
        expect(extractor.extract_id(admin)).to eq('admin:1')
      end

      it 'returns non-prefixed id for unknown mapping' do
        expect(extractor.extract_id(double('User', id: 1))).to eq('1')
        expect(extractor.extract_id(id: 1)).to eq('1')
      end

      it 'returns nil when object is an empty hash' do
        expect(extractor.extract_id({})).to be_nil
      end

      it 'returns nil when object is nil' do
        expect(extractor.extract_id(nil)).to be_nil
      end

      it 'returns prefixed id when object has both id and uuid methods' do
        user = double(id: 1, uuid: 2, class: double(name: 'User'))
        expect(extractor.extract_id(user)).to eq('user:1')
      end

      it 'returns nil when object has class but no id or uuid' do
        user = double(class: double(name: 'User'))
        expect(extractor.extract_id(user)).to be_nil
      end

      it 'returns non-prefixed id when class does not match any mapping' do
        unknown = double(id: 1, class: double(name: 'Unknown'))
        expect(extractor.extract_id(unknown)).to eq('1')
      end

      it 'returns nil when hash has class_name but no id' do
        expect(extractor.extract_id(class: double(name: 'User'))).to be_nil
      end
    end

    context 'when mode is set to identification' do
      let(:extractor) { described_class.new(mode: 'identification') }

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

      it 'returns nil if object does not respond to id or uuid methods' do
        expect(extractor.extract_id(double('User'))).to be_nil
      end
    end

    context 'when mode is set to anonymization' do
      let(:extractor) { described_class.new(mode: 'anonymization') }

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
      let(:extractor) { described_class.new(mode: 'identification') }

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

      it 'returns nil if object does not respond to email or other methods' do
        expect(extractor.extract_login(double('User'))).to be_nil
      end

      it 'returns nil when object is nil' do
        expect(extractor.extract_login(nil)).to be_nil
      end

      it 'returns login when object has only some of the login methods' do
        expect(extractor.extract_login(double('User', username: 'example'))).to eq('example')
        expect(extractor.extract_login(double('User', login: 'example'))).to eq('example')
        expect(extractor.extract_login(double('User', email: 'ex@mple.com'))).to eq('ex@mple.com')
      end

      it 'returns nil when object has class but no login methods' do
        expect(extractor.extract_login(double('User', class: double(name: 'User')))).to be_nil
      end

      it 'returns nil when hash has class but no login keys' do
        expect(extractor.extract_login(class: double(name: 'User'))).to be_nil
      end
    end

    context 'when mode is set to anonymization' do
      let(:extractor) { described_class.new(mode: 'anonymization') }

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

      it 'returns nil if object does not respond to id or uuid methods' do
        expect(extractor.extract_id(double('User'))).to be_nil
      end

      it 'returns consistent anonymization for same input' do
        anon_login_1 = extractor.extract_login(email: 'test@example.com')
        anon_login_2 = extractor.extract_login(email: 'test@example.com')
        anon_login_3 = extractor.extract_login(email: 'different@example.com')

        expect(anon_login_1).to eq(anon_login_2)
        expect(anon_login_1).not_to eq(anon_login_3)
      end

      it 'returns nil when object is nil' do
        expect(extractor.extract_login(nil)).to be_nil
      end
    end
  end
end
