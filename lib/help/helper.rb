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

# API Reference (API Version 2012-07-20): 
# http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-RegisterImage.html
# Check name for AWS AMI registration
# Constraints: 3-128 alphanumeric characters, parenthesis (()), commas (,), slashes (/), dashes (-), or underscores(_)
def check_aws_name(str)
  if str.match(/^[0-9a-z\-\_\(\)\/\,]{1,128}$/i)
    return true
  else
    return false
  end
  return true 
end

# Check description for AWS AMI registration
# Constraints: Up to 255 characters
def check_aws_desc(str)
  if str.size <= 255
    return true
  else
    return false
  end
end
