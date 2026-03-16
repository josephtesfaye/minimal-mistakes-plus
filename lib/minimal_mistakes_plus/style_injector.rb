module MinimalMistakesPlus
  Jekyll::Hooks.register :site, :post_read do |site|
    # Locate the default main.scss file loaded by the Minimal Mistakes theme
    main_scss = site.pages.find { |page| page.name == 'main.scss' && page.dir == '/assets/css/' }

    if main_scss
      # 1. Inject the variables partial right BEFORE the theme imports its skins
      unless main_scss.content.include?('minimal_mistakes_plus/variables')
        main_scss.content = main_scss.content.sub(
          /(@import "minimal-mistakes\/skins)/,
          "@import \"minimal_mistakes_plus/variables\";\n\\1"
        )
      end

      # 2. Dynamically import dark mode (This replaces your old Liquid tags!)
      if site.config['dark_mode_toggle'] && !main_scss.content.include?('minimal_mistakes_plus/dark_mode_toggle')
        main_scss.content = main_scss.content.sub(
          /(@import "minimal-mistakes";?)/,
          "\\1\n@import \"minimal_mistakes_plus/dark_mode_toggle\";"
        )
      end

      # 3. Inject our plugin's core layout modifications after the base theme imports
      unless main_scss.content.include?('minimal_mistakes_plus/main')
        main_scss.content = main_scss.content.sub(
          /(@import "minimal-mistakes";?)/,
          "\\1\n@import \"minimal_mistakes_plus/main\";"
        )
      end
    end
  end
end
