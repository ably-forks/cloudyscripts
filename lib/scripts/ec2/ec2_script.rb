# Base class for any script on EC2.
class Ec2Script
  # Input parameters
  # aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # aws_secret_key => the Amazon AWS Secret Key
  #
  def initialize(input_params)
    @input_params = input_params
  end

end

