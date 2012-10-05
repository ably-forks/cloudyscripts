require 'rubygems'
require 'net/ssh'
require 'AWS'

# =About
# CloudyScripts is a library that implements tasks that support common
# usecases on Cloud Computing Infrastructures (such as Amazon EC2 or Rackspace).
# It aims to facilitate the implementation of usecases that are not directly
# available via the providers' API (e.g. like encrypting storage,
# migrating instances betweem accounts, activating HTTPS). The scripts typically
# use the provider APIs plus remote access to command-line tools installed on
# the instances themselves.
#
# =Installation and Usage
# ===Installation
# <tt>gem install CloudyScripts</tt>
#
# ===Usage
# All scripts are available under /lib/scripts/<em>provider</em>>
#
# ===Scripts
# Here are the scripts implemented so far:
# * #Scripts::EC2::DmEncrypt (encrypt Amazon EBS Storage using dm-encrypt)
#
class CloudyScripts
end
