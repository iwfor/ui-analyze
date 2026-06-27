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

    def self.run(path, from: nil, to: nil, anon: false)
      dump = Dump.open(path)
      info = DeviceInfo.new(dump)
      disk = DiskInfo.new(dump)
      health = HealthInfo.new(dump)
      hist = BootHistory.new(dump)
      az   = anon ? Anonymizer.new(device_name: info.name) : nil

      print_device_info(info, az)
      puts
      print_disk_info(disk, az)
      puts
      print_health(health, az)
      puts
      print_boot_history(hist, from: from, to: to, az: az)
    ensure
      dump&.cleanup
    end

    def self.print_device_info(info, az = nil)
      section "Device Information"

      row "Name",           info.name
      row "Model",          info.model
      row "Serial",         az ? az.serial(info.serial)          : info.serial
      row "MAC Address",    az ? az.mac(info.mac)                : info.mac
      row "QR ID",          az ? az.qr_id(info.qr_id)           : info.qr_id
      row "UUID",           az ? az.uuid(info.uuid)              : info.uuid
      row "Anon ID",        az ? az.anon_id(info.anon_id)        : info.anon_id
      row "Hash ID",        az ? az.hash_id(info.hash_id)        : info.hash_id
      row "BOM",            az ? az.bom(info.bom)                : info.bom
      row "Board Rev",      info.board_revision
      row "Hostname",       az ? az.hostname(info.hostname)      : info.hostname

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

    def self.print_disk_info(disk, az = nil)
      section "Storage"

      # Attached / bay disks with SMART data
      if disk.attached_disks.any?
        disk.attached_disks.each do |d|
          label  = d.slot ? "Bay #{d.slot} Disk" : "Attached Disk"
          size   = (d.size_bytes&.> 0) ? "  #{bytes_human(d.size_bytes)}" : ""
          serial = az ? az.serial(d.serial) : d.serial

          if d.present == false
            snap = d.snapshot_date ? " (last seen #{d.snapshot_date[0, 10]})" : ""
            puts "  #{BOLD}#{label}#{RESET}  #{DIM}#{d.model}#{size}#{RESET}  #{"\e[33m"}⚠ not present#{snap}#{RESET}"
          else
            puts "  #{BOLD}#{label}#{RESET}  #{d.model}#{size}"
          end
          row "  Serial",       serial
          row "  Power-on hrs", d.power_on_hours&.to_s unless d.present == false
          row "  Temperature",  d.temperature_c ? "#{d.temperature_c}°C" : nil unless d.present == false
          row "  Health",       d.life_pct ? "#{d.life_pct}% remaining" : nil
          row "  Bad sectors",  d.bad_sectors&.to_s unless d.present == false
          row "  Error log",    d.error_log_count ? "#{d.error_log_count} entries" : nil unless d.present == false
          puts
        end
      else
        # Show slot inventory even if empty
        slots = disk.storage_slots
        if slots.any?
          slots.each do |s|
            status = s["status"] == "nodisk" ? "#{DIM}(empty)#{RESET}" : s["status"]
            puts "  #{DIM}Bay #{s["slot"]}#{RESET}  #{status}"
          end
          puts
        end
      end

      # System filesystems
      if disk.filesystems.any?
        puts "  #{DIM}#{"Filesystem".ljust(42)}  #{"Size".rjust(7)}  #{"Used".rjust(7)}  #{"Avail".rjust(7)}  #{"Use%".rjust(4)}  Mount#{RESET}"
        puts "  #{DIM}#{"-" * 85}#{RESET}"
        disk.filesystems.each do |fs|
          use_color = fs.use_pct >= 90 ? "\e[31m" : (fs.use_pct >= 75 ? "\e[33m" : "")
          puts "  #{fs.device.ljust(42)}  #{bytes_human(fs.size_bytes).rjust(7)}  " \
               "#{bytes_human(fs.used_bytes).rjust(7)}  #{bytes_human(fs.avail_bytes).rjust(7)}  " \
               "#{use_color}#{fs.use_pct.to_s.rjust(3)}%#{RESET}  #{fs.mount}"
        end
        puts
      end

      # Swap
      if (total = disk.swap_total_bytes)
        used = disk.swap_used_bytes || 0
        free = disk.swap_free_bytes || total
        pct  = total > 0 ? ((used.to_f / total) * 100).round : 0
        use_color = pct >= 50 ? "\e[33m" : ""
        puts "  #{DIM}Swap#{RESET}  #{bytes_human(total)} total, " \
             "#{use_color}#{bytes_human(used)} used#{RESET}, #{bytes_human(free)} free  (#{pct}%)"
      end
    end

    def self.print_health(health, az = nil)
      section "System Health"

      # CPU
      cpu_temp = health.cpu_temperature
      load     = health.load_averages
      loading  = health.cpu_loading

      cpu_temp_str = cpu_temp ? temp_str(cpu_temp) : nil
      load_str     = load ? "#{load[0]} / #{load[1]} / #{load[2]}  (1m / 5m / 15m)" : nil
      load_color   = load && load[0] >= 4 ? (load[0] >= 8 ? "\e[31m" : "\e[33m") : ""

      row "CPU temp",       cpu_temp_str
      if load_str
        puts "  #{DIM}#{"CPU load".ljust(16)}#{RESET}  #{load_color}#{load_str}#{RESET}"
      end
      if loading
        busy = loading["busy"].round(1)
        usr  = loading["usr"].round(1)
        sys  = loading["sys"].round(1)
        puts "  #{DIM}#{"CPU usage".ljust(16)}#{RESET}  #{busy}% busy  (#{usr}% user, #{sys}% sys)"
      end

      # Thermal sensors & fans
      unless health.thermal_sensors.empty?
        puts
        puts "  #{DIM}#{"Sensor".ljust(8)}  #{"Temp".rjust(7)}  #{"Fan".rjust(6)}  Speed#{RESET}"
        puts "  #{DIM}#{"-" * 38}#{RESET}"
        health.thermal_sensors.each do |s|
          color    = temp_color(s.temperature_c)
          raw      = temp_str(s.temperature_c)
          fan_pct  = s.fan_pct       ? "#{s.fan_pct}%" : "—"
          fan_rpm  = s.fan_speed_rpm ? "#{s.fan_speed_rpm} RPM" : (s.fan_pct ? "passive" : "off")
          puts "  Sensor #{s.id}  #{color}#{raw.rjust(7)}#{RESET}  #{fan_pct.rjust(6)}  #{fan_rpm}"
        end
      end

      # Memory pressure
      puts
      total     = health.memory_total_bytes
      avail     = health.memory_available_bytes
      committed = health.memory_committed_bytes

      if total
        avail_pct   = avail ? ((avail.to_f / total) * 100).round : nil
        commit_pct  = committed ? ((committed.to_f / total) * 100).round : nil
        avail_color = avail_pct && avail_pct < 15 ? "\e[31m" : (avail_pct && avail_pct < 25 ? "\e[33m" : "")
        commit_color = commit_pct && commit_pct > 150 ? "\e[31m" : (commit_pct && commit_pct > 100 ? "\e[33m" : "")

        row "RAM total",    bytes_human(total)
        puts "  #{DIM}#{"RAM available".ljust(16)}#{RESET}  #{avail_color}#{bytes_human(avail)}#{avail_pct ? " (#{avail_pct}%)" : ""}#{RESET}" if avail
        puts "  #{DIM}#{"RAM committed".ljust(16)}#{RESET}  #{commit_color}#{bytes_human(committed)}#{commit_pct ? " (#{commit_pct}% of total)" : ""}#{RESET}" if committed
      end

      # OOM pressure events (elevated above table if present)
      pressure = health.memory_pressure_events
      if pressure.any?
        puts
        puts "  \e[31m⚠ OOM pressure detected:\e[0m"
        pressure.each do |e|
          puts "  #{DIM}#{e.name.ljust(36)}#{RESET}  failcnt=#{e.mem_failcnt}  oom_kills=#{e.oom_kills}"
        end
      end

      # Top memory consumers
      consumers = health.top_memory_consumers
      if consumers.any?
        puts
        puts "  #{DIM}#{"Service".ljust(36)}  #{"RSS".rjust(7)}  #{"Swap".rjust(7)}  Total#{RESET}"
        puts "  #{DIM}#{"-" * 68}#{RESET}"
        consumers.each do |e|
          total_bytes = e.mem_bytes + e.swap_bytes
          puts "  #{e.name.ljust(36)}  #{bytes_human(e.mem_bytes).rjust(7)}  #{bytes_human(e.swap_bytes).rjust(7)}  #{bytes_human(total_bytes)}"
        end
      end

      # SFP modules
      sfps = health.sfp_modules
      if sfps.any?
        puts
        sfps.each do |sfp|
          link_str = if sfp.link_up == true
                       "#{"\e[32m"}linked#{RESET} @ #{sfp.speed_mbps}Mb/s"
                     elsif sfp.link_up == false
                       "#{DIM}no link#{RESET}"
                     else
                       "—"
                     end
          serial_val = az ? az.serial(sfp.serial) : sfp.serial
          puts "  #{BOLD}#{sfp.iface}#{RESET}  #{sfp.vendor} #{sfp.part_number}  #{link_str}"
          row "  Serial",      serial_val
          row "  Date",        sfp.date_code
        end
      end
    end

    def self.print_boot_history(hist, from: nil, to: nil, az: nil)
      section "Boot History"

      all_boots = hist.boots
      boots = all_boots.select do |b|
        (from.nil? || b.timestamp >= from) &&
          (to.nil?   || b.timestamp <= to)
      end

      total    = all_boots.length
      filtered = boots.length
      improper = boots.count { |b| b.reason == :improper }
      upgrades = boots.count { |b| b.reason == :firmware_upgrade }

      if from || to
        range_parts = []
        range_parts << "from #{from.strftime("%Y-%m-%d")}" if from
        range_parts << "to #{to.strftime("%Y-%m-%d")}" if to
        puts "  #{DIM}Showing #{filtered} of #{total} boots (#{range_parts.join(" ")})#{RESET}"
        puts
      end

      puts "  #{BOLD}#{filtered} boots#{from || to ? "" : " total"}#{RESET} — " \
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
        detail  = az ? az.scrub(b.reason_detail) : b.reason_detail
        label   = "#{label}: #{detail}" if detail
        label   = "#{label} ⚠ empty bootlog" if b.log_empty && b.reason != :firmware_upgrade

        reason_str = "#{color(b.reason)}#{label}#{RESET}"

        puts "  #{b.index.to_s.rjust(3)}  #{ts.ljust(20)}  " \
             "#{uptime.rjust(10)}  #{fw.ljust(28)}  #{reason_str}"
      end

      puts
      print_reboot_rate_by_firmware(boots, az: az)
    end

    def self.print_reboot_rate_by_firmware(boots, az: nil)
      section "Reboot Rate by Firmware"

      # Group improper shutdowns between each firmware upgrade
      groups = []
      current_fw   = nil
      current_from = nil
      improper_count = 0

      boots.each do |b|
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
      last_boot = boots.last
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

        fw_str = short_fw(g[:fw])
        puts "  #{fw_str.ljust(28)}  #{days.to_s.rjust(10)}d  " \
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

    def self.bytes_human(bytes)
      return "0 B" if bytes.nil? || bytes == 0

      units = %w[B KB MB GB TB]
      exp   = (Math.log(bytes) / Math.log(1024)).to_i
      exp   = units.length - 1 if exp >= units.length
      val   = bytes.to_f / (1024**exp)
      val == val.to_i ? "#{val.to_i} #{units[exp]}" : "#{"%.1f" % val} #{units[exp]}"
    end

    def self.temp_str(c)
      "#{c}°C"
    end

    def self.temp_color(c)
      return "\e[31m" if c >= 80
      return "\e[33m" if c >= 65
      ""
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
