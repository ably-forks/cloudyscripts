require 'audit/lib/benchmark/result_code'
require 'audit/lib/lazy'

class RuleResult
  attr_reader :rule
  attr_reader :check
  attr_reader :rule_idref
  attr_reader :result
  attr_reader :version
  attr_reader :timestamp
  attr_reader :severity

  def initialize(rule, results)
    @timestamp = Time.now.utc
#    @severity = rule.severity
#    @version = rule.version

    return_codes = results.reject {|x| x.type != ResultType::CHECK_FINISHED}
    raise "Each rule should have exacty one return code" if return_codes.length != 1
    return_code = return_codes[0]

    if return_code.exit_code.downcase == "pass" then
      @result = ResultCode::PASS
    else
      @result = ResultCode::FAIL
    end

    @rule_idref = rule.id
    @rule = rule
    @check = results
  end

  def to_hash()
    return {
      :type => :RULE_RESULT,
      :timestamp => @timestamp,
      :rule => @rule_idref,
      :checks => Lazy.new(@check, :map) {|result| Lazy.new(result, :to_hash)},
      :result => @result
    }
  end
end
