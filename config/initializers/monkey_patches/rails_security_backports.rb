# Backports of Rails security fixes (advisories of 2026-11-04) that only shipped in 8.0.5.2 / 8.1.4.1:
# there is no patched 7.2 release. Each method is copied from the official 8.0 patch. Remove this file
# when upgrading to Rails 8 (the guard below already makes it a no-op there).
return unless Rails::VERSION::MAJOR < 8

# GHSA-8474-xrp6-wh69 (High): safe_constantize compiled an unescaped regexp from the constant name.
# Action Cable passes the client-supplied `channel` of every subscribe command to safe_constantize,
# and ApplicationCable::Connection authenticates nobody (the widget connects too), so any visitor
# could crash the process with a crafted pattern.
# Patch: https://github.com/rails/rails/commit/210ac22d446c8e2625b091e79256806b836eee20
module ActiveSupport
  module Inflector
    def safe_constantize(camel_cased_word) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- verbatim from Rails
      constantize(camel_cased_word)
    rescue NameError => e
      raise if e.name && !(camel_cased_word.to_s.split('::').include?(e.name.to_s) ||
        e.name.to_s == camel_cased_word.to_s)
    rescue LoadError => e
      message = e.respond_to?(:original_message) ? e.original_message : e.message
      constant_name = camel_cased_word.split('::').find { |part| !part.empty? } || camel_cased_word
      raise unless message.include?("Unable to autoload constant #{constant_name}")
    end
  end
end

# GHSA-wm3x-v3qw-4jh3 (High): each_key with a block returned the raw indifferent-access hash, which mass
# assignment accepts without a permit. This codebase never uses that return value; backported anyway.
# Patch: https://github.com/rails/rails/commit/2fc8838300133931e19eed3ea6cee76a7e83f19c
ActiveSupport.on_load(:action_controller) do
  ActionController::Parameters.class_eval do
    def each_key(&)
      return to_enum(:each_key) unless block_given?

      @parameters.each_key(&)
      self
    end
  end
end
