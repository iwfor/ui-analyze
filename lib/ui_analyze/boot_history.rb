# frozen_string_literal: true

require "time"

module UiAnalyze
  # Parses and correlates boot events from bootlog entries and reboot-time.log.
  class BootHistory
    Boot = Struct.new(
      :index,        # chronological index (1 = oldest)
      :timestamp,    # Time object
      :slug,         # raw bootlog filename slug (e.g. "boot-20260622111707-etio")
      :firmware,     # "v5.1.19..." string or nil
      :reason,       # :firmware_upgrade | :improper | :normal | :reset | :unknown
      :reason_detail,# raw reboot-time.log line detail (upgrade from/to, duration)
      :log_empty,    # true if bootlog file had no content
      :uptime_prev,  # seconds since previous boot (nil for first)
      keyword_init: true
    )

    def initialize(dump)
      @dump = dump
      @boots = nil
    end

    def boots
      @boots ||= build
    end

    def total
      boots.length
    end

    def improper_count
      boots.count { |b| b.reason == :improper }
    end

    def firmware_upgrades
      boots.select { |b| b.reason == :firmware_upgrade }
    end

    private

    def build
      boot_entries  = parse_bootlogs
      reboot_events = parse_reboot_time_log

      boots = boot_entries.each_with_index.map do |entry, idx|
        ts = entry[:timestamp]

        # Find the matching reboot-time.log event — the entry recorded just
        # after this boot's timestamp (within a few minutes of boot completion)
        event = reboot_events.find do |ev|
          ev[:timestamp] > ts && ev[:timestamp] < ts + 600
        end

        prev_ts = idx > 0 ? boot_entries[idx - 1][:timestamp] : nil
        uptime_prev = prev_ts ? (ts - prev_ts).to_i : nil

        Boot.new(
          index:         idx + 1,
          timestamp:     ts,
          slug:          entry[:slug],
          firmware:      entry[:firmware],
          reason:        event ? event[:reason] : :unknown,
          reason_detail: event ? event[:detail] : nil,
          log_empty:     entry[:empty],
          uptime_prev:   uptime_prev
        )
      end

      boots
    end

    # Parse every file in system/bootlog/ (excluding boot.log summary)
    def parse_bootlogs
      files = @dump.glob("system/bootlog/boot-*").sort
      files.map do |rel|
        slug = File.basename(rel)
        ts   = parse_boot_timestamp(slug)
        next nil unless ts

        content  = @dump.read(rel) || ""
        firmware = content.match(/Curr FW version:\s*(\S+)/)&.[](1)

        { slug: slug, timestamp: ts, firmware: firmware, empty: content.strip.empty? }
      end.compact
    end

    # Parse system/var/log/reboot-time.log
    def parse_reboot_time_log
      text = @dump.read("system/var/log/reboot-time.log") || ""
      text.lines.filter_map do |line|
        line = line.strip
        next if line.empty?

        ts = parse_log_timestamp(line)
        next unless ts

        reason, detail = classify_reboot_line(line)
        { timestamp: ts, reason: reason, detail: detail }
      end
    end

    # Boot filenames: boot-YYYYMMDDHHMMSS-xxxx
    def parse_boot_timestamp(slug)
      m = slug.match(/boot-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})-/)
      return nil unless m

      Time.new(m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, m[6].to_i)
    rescue ArgumentError
      nil
    end

    # reboot-time.log has two timestamp formats:
    #   "2025-06-18 16:24:37,947 ..."
    #   "2026-03-22T03:43:33-0600 ..."
    def parse_log_timestamp(line)
      if (m = line.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/))
        Time.parse(m[1])
      elsif (m = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4})/))
        Time.parse(m[1])
      end
    rescue ArgumentError
      nil
    end

    def classify_reboot_line(line)
      if line.include?("improper shutdown")
        [:improper, nil]
      elsif line.include?("upgrade reboot")
        m = line.match(/upgrade reboot from (\S+) to (\S+)/)
        detail = m ? "#{m[1]} → #{m[2]}" : nil
        [:firmware_upgrade, detail]
      elsif line.include?("normal reboot")
        dur = line.match(/takes (.+)/)&.[](1)
        [:normal, dur]
      elsif line.include?("reset reboot")
        dur = line.match(/takes (.+)/)&.[](1)
        [:reset, dur]
      else
        [:unknown, line]
      end
    end
  end
end
