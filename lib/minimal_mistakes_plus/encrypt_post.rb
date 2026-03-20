require 'openssl'
require 'base64'
require 'nokogiri'
require 'erb'

Jekyll::Hooks.register [:pages, :documents], :post_render, priority: :low do |doc|
  enc = doc.data['encrypted']
  if enc == true || enc == 'true' || enc == 'buttitle'
    doc.data['excerpt'] = "This post is password protected."

    if enc == true || enc == 'true'
      doc.data['title'] = "🔒 Protected Content"
      doc.data['read_time'] = false
    end

    password = ENV['BLOG_PASSWORD']

    if password.nil? || password.empty?
      doc.output.gsub!(/<body>.*<\/body>/m, "<body><p style='color:red;'>Configuration error: Environment variable BLOG_PASSWORD is missing.</p></body>")
      next
    end

    # Parse the fully generated HTML page
    html = Nokogiri::HTML(doc.output)

    if (enc == true || enc == 'true') && doc.data['real_title']
      title_node = html.at_css('h1.page__title')
      title_node.content = doc.data['real_title'] if title_node
    end

    # Target the specific Minimal Mistakes layout blocks
    selectors = [
      'section.page__content',  # The main text + TOC
      'footer.page__meta',      # Tags and categories
      'section.page__share',    # Share block
      'div.page__comments',     # Comments block
      'div.page__related'       # Related posts grid
    ]

    # If fully encrypted, we also strip and encrypt the title header
    if enc == true || enc == 'true'
      selectors.unshift('nav.breadcrumbs', 'header')
    end

    payload = {}

    # Extract the HTML of the targets and replace them with placeholders
    selectors.each do |selector|
      node = html.at_css(selector)
      if node
        payload[selector] = node.to_html
        safe_id = "secure-placeholder-#{selector.gsub(/[^a-zA-Z0-9]/, '-')}"
        node.replace("<div id='#{safe_id}'></div>")
      end
    end

    # Skip if none of the elements are found (e.g., custom layouts)
    next if payload.empty?

    # Encrypt the extracted HTML bundle
    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.encrypt
    iv = cipher.random_iv
    salt = OpenSSL::Random.random_bytes(16)
    key = OpenSSL::PKCS5.pbkdf2_hmac(password.to_s, salt, 10000, cipher.key_len, 'sha256')
    cipher.key = key

    encrypted_data = cipher.update(payload.to_json) + cipher.final

    b64_iv = Base64.strict_encode64(iv)
    b64_salt = Base64.strict_encode64(salt)
    b64_ciphertext = Base64.strict_encode64(encrypted_data)

    # Build the injection UI
    template_path = File.join(doc.site.source, '_includes', 'secure_ui.html')
    secure_ui = ERB.new(File.read(template_path)).result(binding)

    # Inject the UI strictly inside div#main by targeting an inner placeholder
    target_selector = (enc == true || enc == 'true') ? 'header' : 'section.page__content'
    target_id = "secure-placeholder-#{target_selector.gsub(/[^a-zA-Z0-9]/, '-')}"
    injection_node = html.at_css("##{target_id}") || html.at_css("#secure-placeholder-section-page--content")
    injection_node.add_previous_sibling(secure_ui) if injection_node

    # Save the modified HTML back to the document
    doc.output = html.to_html
  end
end
