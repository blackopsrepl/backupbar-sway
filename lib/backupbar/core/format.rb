# frozen_string_literal: true

require "time"

module BackupBar
  module Core
    module Format
      module_function

      def parse_time(value)
        return nil if value.to_s.strip.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def iso_time(time)
        time&.utc&.iso8601(6)
      end

      def age_seconds(value, now = Time.now)
        time = value.is_a?(Time) ? value : parse_time(value)
        return nil unless time

        [now - time, 0].max.to_i
      end

      def duration(seconds)
        value = seconds.to_i
        return "#{value}s" if value < 60
        return "#{value / 60}m" if value < 3_600
        return "#{value / 3_600}h #{(value % 3_600) / 60}m" if value < 86_400

        "#{value / 86_400}d #{(value % 86_400) / 3_600}h"
      end

      def relative_time(value, now = Time.now)
        age = age_seconds(value, now)
        return "unknown" unless age
        return "now" if age < 60

        "#{duration(age)} ago"
      end

      def bytes(value)
        number = value.to_i
        return "0 B" if number <= 0

        units = %w[B KiB MiB GiB TiB]
        index = 0
        scaled = number.to_f
        while scaled >= 1024 && index < units.length - 1
          scaled /= 1024
          index += 1
        end
        precision = scaled >= 10 || index.zero? ? 0 : 1
        "#{scaled.round(precision)} #{units[index]}"
      end

      def percent(value)
        value.nil? ? "--" : "#{value.to_f.round}%"
      end

      def compact_number(value)
        number = value.to_i
        return number.to_s if number < 1_000
        return "#{(number / 1_000.0).round(1)}k" if number < 1_000_000

        "#{(number / 1_000_000.0).round(1)}m"
      end

      def clean_text(value, limit: 280)
        text = value.to_s.gsub(/\s+/, " ").strip
        text.length > limit ? "#{text[0, limit - 3]}..." : text
      end
    end
  end
end
