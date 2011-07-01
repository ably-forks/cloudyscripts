# To change this template, choose Tools | Templates
# and open the template in the editor.

class BenchmarkResult
  attr_reader :audit
  
  def initialize(audit)
    @audit = audit
    @document = {}
  end

  def add(rule_result)
    @document[rule_result.rule.id] = rule_result
  end

  def get(id)
    return @benchmark if id == :root || id == 'BENCHMARK'
    
    return @document[id] || @benchmark.get_item(id)
  end

  def get_root()
    return get(:root)
  end
end
