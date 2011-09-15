require 'logger'
require 'pp'

# Mocked for Audit library
class MockedAuditLib

  attr_reader :results

  def initialize(options)
    @fail = false

    raise "Option :benchmark is required" unless options[:benchmark]
    raise "Option :connection_type is required" unless options[:connection_type]
    raise "Option :connection_params is required" unless options[:connection_params]

    if options[:logger] then
      @logger = options[:logger]
    else
      @logger = Logger.new(STDOUT)
    end
    @logger.level = Logger::ERROR

    @benchmark = nil
    @connection = nil
    @results = {}
    @exceptions = []
    @attachment_dir = options[:attachment_dir]
  end

  def start(parallel = true)
    @results = { "SSH_RES_1" => {:rule => {:description => "SSH description 1"}, :result => "pass" }, 
                 "SSH_RES_2" => {:rule => {:description => "SSH description 2"}, :result => "pass" },
                 "SSH_RES_3" => {:rule => {:description => "SSH description 3"}, :result => "fail" } }
    return self
  end

end
