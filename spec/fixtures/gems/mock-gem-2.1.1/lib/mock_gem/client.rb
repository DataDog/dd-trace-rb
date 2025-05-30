module MockGem
  class Client
    def self.rescue_error
      raise 'mock_gem client error'
    rescue => e
      e
    end
  end
end
