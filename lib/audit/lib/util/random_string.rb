# To change this template, choose Tools | Templates
# and open the template in the editor.

# Ruby 1.8 does not contains sample() function
class Array
  def sample()
    return self.choice() 
  end
end

class RandomString
  def initialize
    
  end
  def self.generate(length = 20, alphabet = ('A' .. 'Z').to_a + ('a' .. 'z').to_a + ('0' .. '9').to_a)
    return (0 .. length).map { alphabet.sample }.join
  end

  def self.generate_name(length = 20)
    return (('A' .. 'Z').to_a + ('a' .. 'z').to_a).sample + generate(length - 1)
  end
end
