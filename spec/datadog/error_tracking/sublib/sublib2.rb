# frozen_string_literal: true
module SubLib2
  def self.rescue_error
    raise 'sublib2 error'
  rescue
    # do nothing
  end
end
