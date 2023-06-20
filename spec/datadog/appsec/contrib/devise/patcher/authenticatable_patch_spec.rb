require 'datadog/appsec/spec_helper'

require 'datadog/appsec/contrib/devise/patcher'
require 'datadog/appsec/contrib/devise/patcher/authenticatable_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patcher::AuthenticatablePatch do
  let(:mock_klass) do
    Class.new do
      prepend Datadog::AppSec::Contrib::Devise::Patcher::AuthenticatablePatch

      def initialize(result)
        @result = result
      end

      def validate(resource, &block)
        @result
      end
    end
  end

  let(:mock_resource) do
    Class.new do
      attr_reader :id, :email, :username

      def initialize(id, email, username)
        @id = id
        @email = email
        @username = username
      end
    end
  end

  let(:nil_resource) { nil }
  let(:resource) { mock_resource.new(1, 'hello@gmail.com', 'John') }
  let(:mode) { 'safe' }
  let(:automated_track_user_events) { double(automated_track_user_events: mode) }
  let(:success_login) { mock_klass.new(true) }
  let(:failed_login) {  mock_klass.new(false) }

  before do
    expect(Datadog::AppSec).to receive(:enabled?).and_return(appsec_enabled)
    expect(Datadog::AppSec).to receive(:settings).and_return(automated_track_user_events) if appsec_enabled

    expect(Datadog::AppSec).to receive(:active_scope).and_return(appsec_scope) if appsec_enabled && mode != 'disable'
  end

  context 'AppSec disabled' do
    let(:appsec_enabled) { false }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)
      expect(success_login.validate(resource)).to eq(true)
    end
  end

  context 'Automated user tracking is disabled' do
    let(:appsec_enabled) { true }
    let(:mode) { 'disable' }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)
      expect(success_login.validate(resource)).to eq(true)
    end
  end

  context 'AppSec scope is nil ' do
    let(:appsec_enabled) { true }
    let(:mode) { 'safe' }
    let(:appsec_scope) { nil }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)
      expect(success_login.validate(resource)).to eq(true)
    end
  end

  context 'successful login' do
    let(:appsec_enabled) { true }
    let(:appsec_scope) { instance_double(Datadog::AppSec::Scope, trace: double, service_entry_span: double) }

    context 'with resource ID' do
      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            **{}
          )
          expect(success_login.validate(resource)).to eq(true)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            **{ username: 'John', email: 'hello@gmail.com' }
          )
          expect(success_login.validate(resource)).to eq(true)
        end
      end
    end

    context 'without resource ID' do
      let(:resource) { mock_resource.new(nil, 'hello@gmail.com', 'John') }

      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            **{}
          )
          expect(success_login.validate(resource)).to eq(true)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            **{ username: 'John', email: 'hello@gmail.com' }
          )
          expect(success_login.validate(resource)).to eq(true)
        end
      end
    end
  end

  context 'unsuccessful login' do
    let(:appsec_enabled) { true }
    let(:appsec_scope) { instance_double(Datadog::AppSec::Scope, trace: double, service_entry_span: double) }

    context 'with resource' do
      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            user_exists: true,
            **{}
          )
          expect(failed_login.validate(resource)).to eq(false)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            user_exists: true,
            **{ username: 'John', email: 'hello@gmail.com' }
          )
          expect(failed_login.validate(resource)).to eq(false)
        end
      end
    end

    context 'without resource' do
      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            user_exists: false,
            **{}
          )
          expect(failed_login.validate(nil_resource)).to eq(false)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            user_exists: false,
            **{}
          )
          expect(failed_login.validate(nil_resource)).to eq(false)
        end
      end
    end
  end
end
