# To change this template, choose Tools | Templates
# and open the template in the editor.

class YamlTransformer
  def initialize
    
  end

  def self.transform(report)
    self.transform_node(report, report.get_root)
  end

  def self.transform_node(report, node)
    if node.kind_of? AuditBenchmark then
      return self.transform_benchmark(report, node)
    elsif node.kind_of? Group then
      return self.transform_group(report, node)
    elsif node.kind_of? RuleResult then
      return self.transform_rule_result(report, node)
    else
      raise "Unknown report node type #{node.class.name}"
    end
  end

  def self.transform_benchmark(report, node)
    return {:id => node.id,
            :name => node.name,
            :description => node.description,
            :children => node.children.map {|x| self.transform_node(report, report.get(x.id))}}
  end

  def self.transform_group(report, node)
    return {:id => node.id,
            :name => node.name,
            :description => node.description,
            :children => node.children.map {|x| self.transform_node(report, report.get(x.id))}}
  end

  def self.transform_rule_result(report, node)
    return {:rule_refid => node.rule.id,
            :name => node.rule.name,
            :description => node.rule.description,
            :check => node.check.map {|x| self.transform_check(x)}
    }
  end

  def self.transform_check(check)
    return check.to_hash()
  end
end
