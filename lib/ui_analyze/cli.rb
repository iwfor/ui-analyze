# frozen_string_literal: true

module UiAnalyze
  module CLI
    REASON_LABEL = {
      firmware_upgrade: "Firmware upgrade",
      improper:         "Improper shutdown",
      normal:           "Normal reboot",
      reset:            "Factory reset",
      unknown:          "Unknown"
    }.freeze

    REASON_COLOR = {
      firmware_upgrade: "\e[34m",  # blue
      improper:         "\e[31m",  # red
      normal:           "\e[32m",  # green
      reset:            "\e[33m",  # yellow
      unknown:          "\e[90m"   # dark gray
    }.freeze

    RESET = "\e[0m"
    BOLD  = "\e[1m"
    DIM   = "\e[2m"

    def self.run(path)
      dump = Dump.open(path)
      info = DeviceInfo.new(dump)
      hist = BootHistory.new(dump)

      print_device_info(info)
      puts
      print_boot_history(hist)
    ensure
      dump&.cleanup
    end

    def self.print_device_info(info)
      section "Device Information"

      row "Name",           info.name
      row "Model",          info.model
      row "Serial",         info.serial
      row "MAC Address",    info.mac
      row "QR ID",          info.qr_id
      row "UUID",           info.uuid
      row "Anon ID",        info.anon_id
      row "Hash ID",        info.hash_id
      row "BOM",            info.bom
      row "Board Rev",      info.board_revision
      row "Hostname",       info.hostname

      puts

      section "Hardware Specs"
      row "CPU",            info.cpu
      row "RAM",            info.ram_human
      row "Flash",          info.flash_human

      puts

      section "Firmware"
      row "Version",        info.firmware_version
      row "Manufactured",   info.mfg_week
    end

    def self.print_boot_history(hist)
      section "Boot History"

      boots = hist.boots
      total = hist.total

      improper = hist.improper_count
      upgrades = hist.firmware_upgrades.length
      puts "  #{BOLD}#{total} boots total#{RESET} — " \
           "#{color(:improper)}#{improper} improper shutdowns#{RESET}, " \
           "#{color(:firmware_upgrade)}#{upgrades} firmware upgrades#{RESET}"
      puts

      # Table header
      puts "  #{DIM}#{"#".rjust(3)}  #{"Timestamp".ljust(20)}  " \
           "#{"Uptime".rjust(10)}  #{"Firmware".ljust(28)}  Reason#{RESET}"
      puts "  #{DIM}#{"-" * 100}#{RESET}"

      boots.each do |b|
        ts      = b.timestamp.strftime("%Y-%m-%d %H:%M:%S")
        uptime  = b.uptime_prev ? format_duration(b.uptime_prev) : "—"
        fw      = b.firmware ? short_fw(b.firmware) : (b.log_empty ? "(empty log)" : "—")
        label   = REASON_LABEL[b.reason] || b.reason.to_s
        label   = "#{label}: #{b.reason_detail}" if b.reason_detail
        label   = "#{label} ⚠ empty bootlog" if b.log_empty && b.reason != :firmware_upgrade

        reason_str = "#{color(b.reason)}#{label}#{RESET}"

        puts "  #{b.index.to_s.rjust(3)}  #{ts.ljust(20)}  " \
             "#{uptime.rjust(10)}  #{fw.ljust(28)}  #{reason_str}"
      end

      puts
      print_reboot_rate_by_firmware(hist)
    end

    def self.print_reboot_rate_by_firmware(hist)
      section "Reboot Rate by Firmware"

      # Group improper shutdowns between each firmware upgrade
      groups = []
      current_fw   = nil
      current_from = nil
      improper_count = 0

      hist.boots.each do |b|
        if b.reason == :firmware_upgrade
          groups << { fw: current_fw, from: current_from, to: b.timestamp, count: improper_count } if current_fw
          current_fw     = b.firmware || "unknown"
          current_from   = b.timestamp
          improper_count = 0
        elsif b.reason == :improper
          current_fw   ||= b.firmware || "unknown"
          current_from ||= b.timestamp
          improper_count += 1
        end
      end
      # Final group (current firmware)
      last_boot = hist.boots.last
      groups << { fw: current_fw || "unknown", from: current_from, to: last_boot&.timestamp, count: improper_count }

      puts "  #{DIM}#{"Firmware".ljust(28)}  #{"Days active".rjust(11)}  " \
           "#{"Crashes".rjust(7)}  Rate#{RESET}"
      puts "  #{DIM}#{"-" * 70}#{RESET}"

      groups.each do |g|
        next unless g[:from] && g[:to]

        days  = ((g[:to] - g[:from]) / 86400.0).round(1)
        rate  = days > 0 ? (days / [g[:count], 1].max).round(1) : "—"
        rate_str = g[:count] > 0 ? "1 per #{rate}d" : "none"
        color_str = g[:count] > 0 ? color(:improper) : color(:normal)

        puts "  #{short_fw(g[:fw]).ljust(28)}  #{days.to_s.rjust(10)}d  " \
             "#{g[:count].to_s.rjust(7)}  #{color_str}#{rate_str}#{RESET}"
      end
    end

    # --- helpers ---

    def self.section(title)
      puts "#{BOLD}#{title}#{RESET}"
      puts "#{DIM}#{"─" * (title.length)}#{RESET}"
    end

    def self.row(label, value)
      return if value.nil? || value.to_s.empty?

      puts "  #{DIM}#{label.ljust(16)}#{RESET}  #{value}"
    end

    def self.color(reason)
      REASON_COLOR[reason] || ""
    end

    # "UDMPRO.al324.v5.1.19.3fbc1da.260613.0944" → "v5.1.19 (260613)"
    def self.short_fw(fw)
      return fw unless fw

      m = fw.match(/\.(v[\d.]+)\.\w+\.(\d{6})/)
      m ? "#{m[1]} (#{m[2]})" : fw
    end

    def self.format_duration(seconds)
      return "—" unless seconds

      if seconds < 3600
        "#{(seconds / 60).round}m"
      elsif seconds < 86_400
        h = seconds / 3600
        m = (seconds % 3600) / 60
        m > 0 ? "#{h}h #{m}m" : "#{h}h"
      else
        d = seconds / 86_400
        h = (seconds % 86_400) / 3600
        h > 0 ? "#{d}d #{h}h" : "#{d}d"
      end
    end
  end
end
