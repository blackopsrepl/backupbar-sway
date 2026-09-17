# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby
BIN = File.join(ROOT, "bin", "backupbar")

Dir.mktmpdir do |root|
  config = File.join(root, "config.json")
  state = File.join(root, "state")
  init = Open3.capture3(RUBY, BIN, "config", "init", "--config", config)
  abort "config init failed: #{init.inspect}" unless init[2].success?

  render = Open3.capture3(RUBY, BIN, "waybar", "render", "--config", config)
  abort "waybar render failed: #{render.inspect}" unless render[2].success?

  payload = JSON.parse(render[0])
  abort "Waybar payload missing text" unless payload["text"]
  abort "state not isolated" if File.directory?(state)
end

puts "BackupBar smoke passed."
