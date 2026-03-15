# frozen_string_literal: true

require_relative "lib/minimal_mistakes_plus/version"

Gem::Specification.new do |spec|
  spec.name = "minimal-mistakes-plus"
  spec.version = MinimalMistakesPlus::VERSION
  spec.authors = ["Joseph Huang"]
  spec.email = ["josephtesfaye022@gmail.com"]

  spec.summary = "A plugin extending the theme Minimal Mistakes"
  spec.description = "It provides or integrates more features besides everything
  in Jekyll and Minimal Mistakes, such as dark mode toggling, drafting in Org
  Mode, numbering headings automatically, managing Kramdown attributes in Org
  files, and encrypting posts with a password, etc."

  spec.homepage = "https://github.com/josephtesfaye/minimal-mistakes-plus/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/josephtesfaye/minimal-mistakes-plus/"
  spec.metadata["changelog_uri"] = "https://github.com/josephtesfaye/minimal-mistakes-plus/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features|docs)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Register dependencies of your gem
  spec.add_dependency "jekyll", "~> 3.9.5"
  spec.add_dependency "minimal-mistakes-jekyll", "~> 4.26"
  spec.add_dependency "nokogiri", "~> 1.14"
  spec.add_dependency "org-ruby", "~> 0.9"
  spec.add_dependency "rouge", "~> 3.30"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
