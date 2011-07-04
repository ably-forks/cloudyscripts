# To change this template, choose Tools | Templates
# and open the template in the editor.

class AutomaticDependencies < Group
  def initialize(childs)
    super("AUTOMATIC_DEPENDENCIES", "automatic dependencies", "checks which are not contained in the benchmark, but neccessary to execute checks in the benchmark")
    @children = childs
  end

  def in_report?()
    false
  end
end
