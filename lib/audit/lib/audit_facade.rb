class AuditFacade
  def start_audit(parameters, &block)
    return Audit.new(parameters, block).start
  end
end
