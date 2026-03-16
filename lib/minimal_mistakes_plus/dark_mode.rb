module MinimalMistakesPlus
  # 1. Add the plugin's _sass directory to Jekyll's global Sass load path
  Jekyll::Hooks.register :site, :after_init do |site|
    sass_dir = File.expand_path("../../_sass", __dir__)
    site.config['sass'] ||= {}
    site.config['sass']['load_paths'] ||= []
    site.config['sass']['load_paths'] << sass_dir unless site.config['sass']['load_paths'].include?(sass_dir)
  end

  # 2. Register the JS file to be automatically copied to _site/assets/js/
  Jekyll::Hooks.register :site, :post_read do |site|
    next unless site.config['dark_mode_toggle']
    gem_dir = File.expand_path("../../", __dir__)
    site.static_files << Jekyll::StaticFile.new(site, gem_dir, 'assets/js', 'dark_mode_toggle.js')
  end

  # 3. High-performance Regex injection for the HTML UI
  Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
    next unless doc.site.config['dark_mode_toggle']
    next unless doc.output.include?('greedy-nav') # Only process pages with a top nav

    baseurl = doc.site.config['baseurl'] || ''
    script_tag = %Q{<script src="#{baseurl}/assets/js/dark_mode_toggle.js"></script>}
    button_tag = '<button class="theme-toggle-btn" onclick="switchTheme()"><i class="fas fa-moon"></i></button>'

    # Inject Script right before </head>
    unless doc.output.include?('<script src="' + baseurl + '/assets/js/dark_mode_toggle.js"')
      doc.output = doc.output.sub('</head>', "  #{script_tag}\n</head>")
    end

    # Inject Button right after the Search Toggle or before the Greedy Nav Hamburger
    unless doc.output.include?('<button class="theme-toggle-btn"')
      if doc.output.include?('class="search__toggle"')
        doc.output = doc.output.sub(/(<button[^>]*class="search__toggle"[^>]*>.*?<\/button>)/m, "\\1\n        #{button_tag}")
      else
        doc.output = doc.output.sub(/(<button[^>]*class="greedy-nav__toggle")/, "#{button_tag}\n        \\1")
      end
    end
  end
end
