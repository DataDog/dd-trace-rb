require 'spec_helper'

require 'datadog/tracing/metadata/tagging'
require 'datadog/tracing/metadata/errors'

RSpec.describe Datadog::Tracing::Metadata::Errors do
  subject(:test_object) { test_class.new }
  let(:test_class) do
    Class.new do
      include Datadog::Tracing::Metadata::Tagging
      include Datadog::Tracing::Metadata::Errors
    end
  end

  ['set_error', 'set_error_tags'].each do |method_name|
    describe "##{method_name}" do
      subject(:error_setter) { test_object.send(method_name, error) }

      let(:error) { RuntimeError.new('oops') }
      let(:backtrace) { %w[method1 method2 method3] }

      before { error.set_backtrace(backtrace) }

      it do
        error_setter

        expect(test_object).to have_error_message('oops')
        expect(test_object).to have_error_type('RuntimeError')
        backtrace.each do |method|
          expect(test_object).to have_error_stack(include(method))
        end
      end
    end
  end
end
