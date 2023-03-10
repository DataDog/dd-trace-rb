require 'datadog/core/vendor/ipaddr'
require 'ipaddr'
require 'ostruct'

RSpec.describe Datadog::Core::Vendor::IPAddr do
  let(:invalid_object) { OpenStruct.new.tap { |o| o.instance_variable_set(:@addr, nil) } }

  describe '.private?' do
    it 'correctly raises when object is invalid' do
      expect { described_class.private?(invalid_object) }.to raise_error(::IPAddr::AddressFamilyError)
    end
  end

  describe '.link_local?' do
    it 'correctly raises when object is invalid' do
      expect { described_class.link_local?(invalid_object) }.to raise_error(::IPAddr::AddressFamilyError)
    end
  end

  describe '.loopback?' do
    it 'correctly raises when object is invalid' do
      expect { described_class.loopback?(invalid_object) }.to raise_error(::IPAddr::AddressFamilyError)
    end
  end
end
