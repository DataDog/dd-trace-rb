# Note: This is a partial vendor. Only functions that are needed by `dd-trace-rb`` were vendored.

#
# = IPAddress
#
# A ruby library to manipulate IPv4 and IPv6 addresses
#
#
# Package::     IPAddress
# Author::      Marco Ceresa <ceresa@ieee.org>
# License::     Ruby License
#
#--
#
#++

module IPAddress

  NAME            = "IPAddress"
  GEM             = "ipaddress"
  AUTHORS         = ["Marco Ceresa <ceresa@ieee.org>"]

  #
  # Checks if the given string is a valid IP address,
  # either IPv4 or IPv6
  #
  # Example:
  #
  #   IPAddress::valid_ip? "2002::1"
  #     #=> true
  #
  #   IPAddress::valid_ip? "10.0.0.256"
  #     #=> false
  #
  def self.valid_ip?(addr)
    valid_ipv4?(addr) || valid_ipv6?(addr)
  end

  #
  # Checks if the given string is a valid IPv4 address
  #
  # Example:
  #
  #   IPAddress::valid_ipv4? "2002::1"
  #     #=> false
  #
  #   IPAddress::valid_ipv4? "172.16.10.1"
  #     #=> true
  #
  def self.valid_ipv4?(addr)
    if /^(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})$/ =~ addr
      return $~.captures.all? {|i| i.to_i < 256}
    end
    false
  end

  #
  # Checks if the given string is a valid IPv6 address
  #
  # Example:
  #
  #   IPAddress::valid_ipv6? "2002::1"
  #     #=> true
  #
  #   IPAddress::valid_ipv6? "2002::DEAD::BEEF"
  #     #=> false
  #
  def self.valid_ipv6?(addr)
    # https://gist.github.com/cpetschnig/294476
    # http://forums.intermapper.com/viewtopic.php?t=452
    return true if /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$/ =~ addr
    false
  end


end
