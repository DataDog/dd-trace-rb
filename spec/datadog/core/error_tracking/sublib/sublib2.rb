module SubLib2
  def self.rescue_error
    begin
      raise 'sublib2 error'
    rescue
      # do nothing
    end
  end
end
