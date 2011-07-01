# To change this template, choose Tools | Templates
# and open the template in the editor.

# icons taken from http://www.famfamfam.com/lab/icons/silk/

require 'benchmark/audit_benchmark'
require 'parser/result_type'
require 'logger'

class WebViewTransformer
  IMAGE_PREFIX = "/images"
  BENCHMARK_ID = "BENCHMARK"

  @@LOG = Logger.new(STDOUT)


  def self.get(audit, id)
    if (id == :root) then
      item = audit.benchmark
     return {
      'data'     => {
        'title'    => item.name || item.id,
        'attr'     => {},
        'icon'     => 'folder'},
      'attr'     => {
        'id'       => BENCHMARK_ID},
      'state'    => 'closed'}
    else
      return self.get_children(audit, id)
    end
  end

  def self.get_children(audit, id)
    if id == BENCHMARK_ID then
      item = audit.benchmark
    else
      item = audit.results[id] || audit.benchmark.item_repository[id]
    end
    
    if item.kind_of? AuditBenchmark then
      return item.children.map {|x| self.get_item(audit, x.id)}
    elsif item.kind_of? Group then
      return item.children.map {|x| self.get_item(audit, x.id)}
    elsif item.kind_of? RuleResult then
      if item.rule.description then
        results = [{
              'data'     => {
               'title'    => item.rule.description,
               'icon'     => "#{IMAGE_PREFIX}/tag_blue.png"},
              'state'    => 'opened',
              'children' => []
            }]
      else
        results = []
      end

      results = results + item.check.reject do|x|
         x.methods.include?(:visible?) && (!x.visible?())
      end.map do |x|
          case x.type
          when ResultType::MESSAGE then
            {
              'data' => {
                'title' => x.to_string(),
                'icon' => "#{IMAGE_PREFIX}/script.png"},
              'state' => 'opened',
              'children' => []
            }
          when ResultType::DATA then
            {
              'data' => {
                'title' => x.to_string(),
                'icon' => "#{IMAGE_PREFIX}/brick.png"},
              'state' => 'opened',
              'children' => []
            }
          when ResultType::PROGRAM_NAME then
            {
              'data' => {
                'title' => x.to_string(),
                'icon' => "#{IMAGE_PREFIX}/cog.png"},
              'state' => 'opened',
              'children' => []
            }
          else
            {
              'data' => {
                'title' => x.to_string(),
                'icon' => "file"},
              'state' => 'opened',
              'children' => []
            }
          end
      end

      return results
    elsif item.kind_of? Check then
      #check was not executed, thus no result
      if item.description then
        return [{
              'data'     => {
                'title'    => item.description,
                'icon'     => "#{IMAGE_PREFIX}/tag_blue.png"},
              'state'    => 'opened',
              'children' => []
            }]
      else
        return []
      end
    else
      raise "Unknown item type #{item.class.name}"
    end
  end

  def self.get_item(audit, id)
    item = audit.results[id] || audit.benchmark.item_repository[id]

    if item.kind_of? AuditBenchmark then
      return {
      'data'     => {
        'title'    => item.name || item.id,
        'icon'     => 'folder'},
      'attr'     => {'id' => 'BENCHMARK'},
      'state'    => 'closed'}
    elsif item.kind_of? Group then
      return {
      'data'     => {
        'title'    => item.name || item.id,
        'icon'     => 'folder'},
        'attr'     => {'id' => item.id},
      'state'    => 'closed'}
    elsif item.kind_of? RuleResult then
       return {
        'data'     => {
          'title'    => item.rule.name || item.rule.id,
          'icon'     => case item.result
              when ResultCode::PASS then "#{IMAGE_PREFIX}/tick.png"
              when ResultCode::FAIL then
                if (item.severity == RuleSeverity::LOW || item.severity == RuleSeverity::INFO) then
                  "#{IMAGE_PREFIX}/warning.png"
                else
                  "#{IMAGE_PREFIX}/fail.png"
                end
              else "#{IMAGE_PREFIX}/question.png"
            end},
        'attr'     => { 'id' => item.rule.id},
        'state'    => 'closed'}
    elsif item.kind_of? Check then
      if item.description then
        return {
        'data'     => {
          'title'    => item.name || item.id,
          'icon'     => "#{IMAGE_PREFIX}/hourglass.png"},
        'attr'     => {'id' => item.id},
        'state'    => 'closed'}
      else
        return {
        'data'     => {
          'title'    => item.name || item.id,
          'icon'     => "#{IMAGE_PREFIX}/hourglass.png"},
        'attr'     => {'id' => item.id},
        'state'    => 'opened',
        'children' => []}
      end
    else
      raise "Unknown item type #{item.class.name} for id #{id}"
    end
  end

  
end
