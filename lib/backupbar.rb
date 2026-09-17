# frozen_string_literal: true

require_relative "backupbar/core/config"
require_relative "backupbar/core/process"
require_relative "backupbar/core/format"
require_relative "backupbar/core/collectors"
require_relative "backupbar/runtime/state"
require_relative "backupbar/runtime/presenter"
require_relative "backupbar/runtime/daemon"
require_relative "backupbar/runtime/quickshell"
require_relative "backupbar/runtime/waybar"
require_relative "backupbar/cli"

module BackupBar
  VERSION = "0.1.0"
end
