# frozen_string_literal: true

module MockGem
  module Utils
    def self.rescue_error
      raise 'mock_gem utils error'
    rescue => e
      e
    end
  end
end
