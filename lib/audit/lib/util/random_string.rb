# To change this template, choose Tools | Templates
# and open the template in the editor.

# Ruby 1.8 does not contains sample() function
# NB:
#   - ruby 1.8.6 has no equivalent method
#   - ruby 1.8.7 has choice() method
#   - ruby 1.9 has sample() method
class Array
  def sec_sample()
    if self.respond_to?(:sample, true)
      return self.sample()
    elsif self.respond_to?(:choice, true)
      return self.choice() 
    else
      return (('A' .. 'Z').to_a + ('a' .. 'z').to_a + ('0' .. '9').to_a)[Kernel.srand.modulo(62)]
    end
  end
end

class RandomString
  def initialize
  end

  def self.generate(length = 20, alphabet = ('A' .. 'Z').to_a + ('a' .. 'z').to_a + ('0' .. '9').to_a)
    return (0 .. length).map { alphabet.sec_sample }.join
  end

  def self.generate_name(length = 20)
    return (('A' .. 'Z').to_a + ('a' .. 'z').to_a).sec_sample + generate(length - 1)
  end
end
