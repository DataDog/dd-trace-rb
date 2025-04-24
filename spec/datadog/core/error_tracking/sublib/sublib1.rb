module SubLib1
  def self.rescue_error
    begin
      raise 'sublib1 error'
    rescue
      # do nothing
    end
  end
end
