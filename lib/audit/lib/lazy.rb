# To change this template, choose Tools | Templates
# and open the template in the editor.

class Lazy
  def initialize(obj, eval_method, *eval_args, &eval_block)
    @obj = obj
    @eval_method = eval_method
    @eval_args = *eval_args
    @eval_block = eval_block

    #debugging
    raise "Object #{@obj.class.name} does not contain method #{@eval_method}" unless @obj.methods.include? @eval_method
  end

  def method_missing(method, *args, &block)
    @evaluated = @obj.send(@eval_method, *@eval_args, &@eval_block) if @evaluated.nil?
    @evaluated.send(method, *args, &block)
  end

  def to_yaml(opts = {})
    @evaluated = @obj.send(@eval_method, *@eval_args, &@eval_block) if @evaluated.nil?
    return @evaluated.to_yaml(opts)
  end

  def methods()
    @evaluated = @obj.send(@eval_method, *@eval_args, &@eval_block) if @evaluated.nil?
    return @evaluated.methods()
  end

  def debug_lazy()
    return [@obj, @eval_method, @eval_args, @eval_block]
  end
  
  def get()
	  return @obj
  end
end
