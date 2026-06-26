# frozen_string_literal: true

module UiAnalyze
  # Parses device identity, hardware specs, and firmware info from a Dump.
  class DeviceInfo
    attr_reader :dump

    def initialize(dump)
      @dump = dump
      @sysid   = parse_kv(dump.read("system/system-id.txt"))
      @hwinfo  = parse_kv(dump.read("system/kernel/ubnthal.system.info"))
    end

    def name
      @sysid["board.name"] || @hwinfo["name"] || "Unknown"
    end

    def short_name
      @sysid["board.shortname"] || @hwinfo["shortname"]
    end

    def model
      @sysid["board.storename"] || short_name
    end

    def serial
      (@sysid["board.serialno"] || @hwinfo["serialno"] || "").upcase
    end

    def mac
      # Serial is the base MAC on UDM devices (lower-cased, colon-separated)
      raw = serial.downcase
      raw.scan(/../).join(":")
    end

    def qr_id
      @sysid["board.qrid"] || @hwinfo["qrid"]
    end

    def uuid
      @sysid["board.uuid"]
    end

    def anon_id
      @hwinfo["device.anonid"]
    end

    def hash_id
      @hwinfo["device.hashid"]
    end

    def bom
      @sysid["board.bom"]
    end

    def board_revision
      rev = @hwinfo["boardrevision"] || @sysid["board.hwrev"]
      return nil unless rev

      rev.start_with?("0x") ? rev.to_i(16).to_s : rev
    end

    def cpu
      @hwinfo["cpu"]
    end

    def ram_bytes
      val = @hwinfo["ramsize"]
      val&.to_i
    end

    def ram_human
      bytes = ram_bytes
      return "Unknown" unless bytes

      gb = bytes / (1024.0 ** 3)
      "#{gb.ceil} GB"
    end

    def flash_bytes
      val = @hwinfo["flashSize"]
      val&.to_i
    end

    def flash_human
      bytes = flash_bytes
      return "Unknown" unless bytes

      mb = bytes / (1024.0 ** 2)
      "#{mb} MB"
    end

    def firmware_version
      fw = dump.read("system/system-version")&.strip
      return fw if fw

      # Fall back to parsing from a boot log
      boot_fw = dump.read("system/bootlog/boot.log")
      boot_fw&.match(/Curr FW version: (\S+)/)&.[](1)
    end

    def hostname
      # kern.log lines with an ISO timestamp include the hostname:
      # "2025-09-13T18:35:32-06:00 Zombie-Road kernel: ..."
      text = dump.read("system/var/log/kern.log") || ""
      # Use the last matching line — early boot lines may show default hostname
      line = text.lines.select { |l| l.match?(/\d{4}-\d{2}-\d{2}T.*kernel:/) }.last
      line&.match(/\S+\s+(\S+)\s+kernel:/)&.[](1)
    end

    def mfg_week
      week = @hwinfo["mfgweek"]
      return nil unless week&.match?(/\A\d{6}\z/)

      year = week[0..3]
      wk   = week[4..5].to_i
      "Week #{wk}, #{year}"
    end

    private

    def parse_kv(text)
      return {} if text.nil? || text.empty?

      text.lines.each_with_object({}) do |line, h|
        key, val = line.chomp.split("=", 2)
        h[key.strip] = val&.strip if key
      end
    end
  end
end
