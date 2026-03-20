require 'fileutils'
require 'shellwords'

Jekyll::Hooks.register :site, :post_read do |site|
  next if Jekyll.env == 'production'

  # Store the intended symlinks so we can recreate them in the _site folder later
  site.config['dynamic_symlinks'] ||= {}

  docs = site.pages + site.collections.values.flat_map(&:docs)
  docs.each do |doc|
    next unless doc.data['symlinks'].is_a?(Array)

    doc.data['symlinks'].each do |symlink_def|
      next unless symlink_def.is_a?(String)

      parts = Shellwords.split(symlink_def)
      next unless parts.size == 2

      link_path_raw, target_path_raw = parts

      target_path = File.expand_path(target_path_raw)
      relative_link_path = link_path_raw.sub(%r{^/}, '')
      link_path = File.join(site.dest, relative_link_path)

      # Verify target exists
      unless File.exist?(target_path)
        Jekyll.logger.warn "Symlink Plugin:", "Skipped. Target does not exist: #{link_path} -> #{target_path}"
        next
      end

      # Save for the post_write phase
      site.config['dynamic_symlinks'][relative_link_path] = {
        target: target_path,
        link: link_path
      }
    end
  end
end

# Inject the symlinks directly into the final build folder
Jekyll::Hooks.register :site, :post_write do |site|
  next if Jekyll.env == 'production'

  symlinks = site.config['dynamic_symlinks'] || {}
  symlinks.each do |relative_path, link|
    target_path = link[:target]
    link_path = link[:link]
    needs_creation = false

    # If the link already exists but is broken, recreate it. If it's not broken
    # or is a file or directory, leave it. Otherwise, create the link.
    if File.symlink?(link_path)
      if !File.exist?(link_path)
        File.unlink(link_path)
        needs_creation = true
      elsif File.readlink(link_path) != target_path # Link has valid target
        Jekyll.logger.warn "Symlink Plugin: Symlink already exists: #{link_path}"
      end
    elsif !File.exist?(link_path)
      needs_creation = true
    else                        # Link path is taken by a file or directory
      Jekyll.logger.warn "Symlink Plugin: Symlink path is taken: #{link_path}"
    end

    if needs_creation
      FileUtils.mkdir_p(File.dirname(link_path))
      begin
        File.symlink(target_path, link_path)
        # Jekyll.logger.info "Symlink Plugin:", "Symlink created: #{link_path} -> #{target_path}"
      rescue => e
        Jekyll.logger.warn "Symlink Plugin:", "Failed to create symlink #{link_path}: #{e.message}"
      end
    end
  end
end
