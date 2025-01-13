require 'spec_helper'
require 'json'

RSpec.describe 'Dynamic Instrumentation' do
  include_context 'integration test'
  di_test

  describe 'ActiveRecord integration' do
    let(:response) { get('di/ar_serializer') }
    subject { JSON.parse(response.body) }

    it 'is loaded' do
      expect(response.code).to eq '200'

      # If AR integration is loaded, this output will be the result of
      # the custom serializer.
      # If AR integration is not loaded, the output here will have a bunch of
      # internal AR fields but not the attributes themselves.
      expect(subject).to match(
        {"type"=>"Test",
         "entries"=>
          [[{"type"=>"Symbol", "value"=>"attributes"},
            {"type"=>"Hash",
             "entries"=>
              [[{"type"=>"String", "value"=>"id"}, {"type"=>"Integer", "value"=>String}],
               [{"type"=>"String", "value"=>"version"}, {"type"=>"NilClass", "isNull"=>true}],
               [{"type"=>"String", "value"=>"data"}, {"type"=>"NilClass", "isNull"=>true}],
               [{"type"=>"String", "value"=>"created_at"},
                {"type"=>"ActiveSupport::TimeWithZone", "value"=>String}],
               [{"type"=>"String", "value"=>"updated_at"},
                {"type"=>"ActiveSupport::TimeWithZone", "value"=>String}]]}],
           [{"type"=>"Symbol", "value"=>"new_record"}, {"type"=>"FalseClass", "value"=>"false"}]]}
      )
    end
  end
end
