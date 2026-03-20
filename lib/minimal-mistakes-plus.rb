# frozen_string_literal: true

require_relative "minimal_mistakes_plus/version"

# Require all of your custom Jekyll plugin scripts
require_relative "minimal_mistakes_plus/org_converter"
require_relative "minimal_mistakes_plus/dark_mode"
require_relative "minimal_mistakes_plus/style_injector"
require_relative "minimal_mistakes_plus/link_abbr"
require_relative "minimal_mistakes_plus/liquify"
require_relative "minimal_mistakes_plus/symlink_external_assets"

module MinimalMistakesPlus
  class Error < StandardError; end
  # Your code goes here...
end
