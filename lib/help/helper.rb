#
# Function that can be used in the whole library
#


# Check if string is not more than 255 character and contains wide char
def check_string_alnum(str)
  if str.match(/^[0-9a-z\-\_\ ]{1,255}$/i)
    return true
  else
    return false
  end
  return true
end
