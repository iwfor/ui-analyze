# frozen_string_literal: true

require "json"

module UiAnalyze
  class HealthInfo
    ThermalSensor = Struct.new(
      :id, :temperature_c, :fan_speed_rpm, :fan_pct,
      keyword_init: true
    )

    CgroupEntry = Struct.new(
      :name, :mem_bytes, :swap_bytes, :mem_failcnt, :oom_kills,
      keyword_init: true
    )

    SfpModule = Struct.new(
      :iface, :vendor, :part_number, :serial, :date_code,
      :speed_mbps, :link_up,
      keyword_init: true
    )

    def initialize(dump)
      @dump = dump
    end

    # CPU temperature (°C) from ustorage hardware.cpu
    def cpu_temperature
      hardware.dig("cpu", "1", "temperature")
    end

    # Per-core load: { busy:, sys:, usr: } or nil
    def cpu_loading
      hardware.dig("cpu", "1", "loading")
    end

    # Load averages [1m, 5m, 15m] from top
    def load_averages
      @load_averages ||= parse_load_averages
    end

    # Array of ThermalSensor (board sensors, not CPU)
    def thermal_sensors
      @thermal_sensors ||= parse_thermal
    end

    # All cgroup entries with non-zero memory, sorted by total (mem+swap) desc
    def cgroup_services
      @cgroup_services ||= parse_cgroups
    end

    # Services with mem_failcnt > 0 or oom_kills > 0
    def memory_pressure_events
      cgroup_services.select { |e| e.mem_failcnt > 0 || e.oom_kills > 0 }
    end

    # Top N memory consumers (services only, not slices)
    def top_memory_consumers(n = 10)
      cgroup_services
        .select { |e| e.name.end_with?(".service") || !e.name.include?(".") }
        .reject { |e| e.mem_bytes == 0 && e.swap_bytes == 0 }
        .first(n)
    end

    # Committed vs available memory from meminfo
    def memory_committed_bytes
      @memory_committed_bytes ||= parse_meminfo_field("Committed_AS")
    end

    def memory_total_bytes
      @memory_total_bytes ||= parse_meminfo_field("MemTotal")
    end

    def memory_available_bytes
      @memory_available_bytes ||= parse_meminfo_field("MemAvailable")
    end

    # SFP/transceiver modules
    def sfp_modules
      @sfp_modules ||= parse_sfps
    end

    private

    def hardware
      @hardware ||= begin
        text = @dump.read("system/storage/ustorage.debug.dump")
        text ? JSON.parse(text).fetch("hardware", {}) : {}
      rescue JSON::ParserError
        {}
      end
    end

    def parse_load_averages
      text = @dump.read("system/process/top")
      return nil unless text
      m = text.match(/load average:\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)/)
      m ? [m[1].to_f, m[2].to_f, m[3].to_f] : nil
    end

    def parse_thermal
      sensors = hardware.fetch("thermal", {})
      sensors.map do |_id, s|
        fan_config = s["fan_config"].to_i
        fan_speed  = s["fan_speed"].to_i
        ThermalSensor.new(
          id:             s["id"],
          temperature_c:  s["temperature"],
          fan_speed_rpm:  fan_speed > 0 ? fan_speed : nil,
          fan_pct:        fan_config > 0 ? fan_config : nil
        )
      end.sort_by(&:id)
    end

    def parse_cgroups
      text = @dump.read("system/cgroup/mem-usage")
      return [] unless text

      entries = []
      text.each_line do |line|
        # "unifi.service mem: 457388032, swap: 22323200, mem_failcnt: 0, oom_kill: 0"
        m = line.match(/^(.+?)\s+mem:\s*(\d+),\s*swap:\s*(\d+),\s*mem_failcnt:\s*(\d+),\s*oom_kill:\s*(\d+)/)
        next unless m
        entries << CgroupEntry.new(
          name:         m[1].strip,
          mem_bytes:    m[2].to_i,
          swap_bytes:   m[3].to_i,
          mem_failcnt:  m[4].to_i,
          oom_kills:    m[5].to_i
        )
      end

      entries.sort_by { |e| -(e.mem_bytes + e.swap_bytes) }
    end

    def parse_sfps
      hw_sfps = hardware.fetch("sfps", {})
      hw_links = hardware.fetch("links", {})
      modules = []

      hw_sfps.each do |iface, info|
        next if info.keys == ["bad-eeprom"] && info["bad-eeprom"] == false && info.size == 1
        next if info["bad-eeprom"] == true

        link = hw_links[iface] || {}
        modules << SfpModule.new(
          iface:       iface,
          vendor:      info["vendor-name"]&.strip,
          part_number: info["vendor-pn"]&.strip,
          serial:      info["vendor-sn"]&.strip,
          date_code:   info["br-nominal"] ? nil : nil, # date from ethtool text instead
          speed_mbps:  link["speed_mbps"],
          link_up:     link["detected"]
        )
      end

      # Enrich with date_code from sfp.txt (more reliably parsed)
      sfp_text = @dump.read("system/network/sfp.txt") || ""
      current_iface = nil
      sfp_text.each_line do |line|
        if (m = line.match(/^(\w+)\s+data:/))
          current_iface = m[1]
        elsif (m = line.match(/Date\s+(\d{6})/))
          mod = modules.find { |s| s.iface == current_iface }
          if mod && m[1].length == 6
            y, mo, d = "20#{m[1][0, 2]}", m[1][2, 2], m[1][4, 2]
            mod.date_code = "#{y}-#{mo}-#{d}"
          end
        end
      end

      modules
    end

    def parse_meminfo_field(field)
      text = @dump.read("system/memory/meminfo")
      return nil unless text
      line = text.lines.find { |l| l.start_with?("#{field}:") }
      return nil unless line
      line.split[1].to_i * 1024
    end
  end
end
