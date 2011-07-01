class RuleSeverity
	UNKNOWN = "unknown"
	INFO = "info"
	LOW = "low"
	MEDIUM = "medium"
	HIGH = "high"
	
	SEVERITIES = [UNKNOWN, INFO, LOW, MEDIUM, HIGH]
	
	def self.parse(str)
		return ((SEVERITIES.include? str.downcase) ? str.downcase : UNKNOWN)
	end
end