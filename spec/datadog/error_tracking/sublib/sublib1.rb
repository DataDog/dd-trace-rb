module SubLib1
  def self.rescue_error
    raise 'sublib1 error'
  rescue
    # do nothing
  end
end
