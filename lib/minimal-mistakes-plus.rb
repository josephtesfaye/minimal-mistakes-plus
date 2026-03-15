# frozen_string_literal: true

require_relative "minimal_mistakes_plus/version"

# Require all of your custom Jekyll plugin scripts
require_relative "minimal_mistakes_plus/org_converter"

module MinimalMistakesPlus
  class Error < StandardError; end
  # Your code goes here...
end
