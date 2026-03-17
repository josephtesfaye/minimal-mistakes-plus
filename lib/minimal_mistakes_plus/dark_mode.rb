module MinimalMistakesPlus
  # 1. Add the plugin's _sass directory to Jekyll's global Sass load path
  Jekyll::Hooks.register :site, :after_init do |site|
    sass_dir = File.expand_path("../../_sass", __dir__)
    site.config['sass'] ||= {}
    site.config['sass']['load_paths'] ||= []
    site.config['sass']['load_paths'] << sass_dir unless
      site.config['sass']['load_paths'].include?(sass_dir)

    # Inject the plugin's _includes directory to natively override the theme
    includes_dir = File.expand_path("../../_includes", __dir__)
    site.includes_load_paths.insert(1, includes_dir) unless
      site.includes_load_paths.include?(includes_dir)
  end

  # 2. Register the JS file to be automatically copied to _site/assets/js/
  Jekyll::Hooks.register :site, :post_read do |site|
    next unless site.config['dark_mode_toggle']
    gem_dir = File.expand_path("../../", __dir__)
    site.static_files << Jekyll::StaticFile.new(site, gem_dir, 'assets/js', 'dark_mode_toggle.js')
  end
end
