# frozen_string_literal: true

require "json"

module UiAnalyze
  # Parses disk, filesystem, and swap information from a Dump.
  class DiskInfo
    Filesystem = Struct.new(
      :device, :mount, :size_bytes, :used_bytes, :avail_bytes, :use_pct,
      keyword_init: true
    )

    AttachedDisk = Struct.new(
      :serial, :model, :size_bytes, :slot,
      :power_on_hours, :temperature_c, :life_pct,
      :bad_sectors, :error_log_count,
      :present,       # false = slot is currently empty; disk_info.json is historical
      :snapshot_date, # date disk_info.json was captured
      keyword_init: true
    )

    def initialize(dump)
      @dump = dump
    end

    # Parsed rows from `df` — real block devices only (no tmpfs/devtmpfs/overlay/loop)
    def filesystems
      @filesystems ||= parse_df
    end

    # Disks from disk_info.json (externally attached / bay disks with SMART data)
    def attached_disks
      @attached_disks ||= parse_disk_info
    end

    # Slot inventory from ustorage — shows empty bays too
    def storage_slots
      @storage_slots ||= parse_storage_slots
    end

    def swap_total_bytes
      @swap_total_bytes ||= parse_meminfo_field("SwapTotal")
    end

    def swap_used_bytes
      total = parse_meminfo_field("SwapTotal")
      free  = parse_meminfo_field("SwapFree")
      return nil unless total && free

      total - free
    end

    def swap_free_bytes
      @swap_free_bytes ||= parse_meminfo_field("SwapFree")
    end

    private

    def parse_df
      text = @dump.read("system/storage/df") || ""
      rows = []

      text.lines.each do |line|
        # Skip header and tmpfs/devtmpfs/overlay/squashfs/loop lines
        next if line.start_with?("Filesystem") || line.strip.empty?
        next if line.match?(%r{^(udev|tmpfs|overlayfs|/dev/loop)})

        parts = line.split
        next unless parts.length >= 6

        device, size_h, used_h, avail_h, use_pct, mount = parts
        rows << Filesystem.new(
          device:     device,
          mount:      mount,
          size_bytes:  parse_df_size(size_h),
          used_bytes:  parse_df_size(used_h),
          avail_bytes: parse_df_size(avail_h),
          use_pct:    use_pct.to_i
        )
      end

      rows
    end

    def parse_disk_info
      text = @dump.read("system/var/log/disk_info.json")
      return [] unless text
      data = JSON.parse(text)

      snapshot_date = data["_date_time"]

      # Occupied slots according to the current ustorage state
      occupied_slots = storage_slots.reject { |s| s["state"] == "nodisk" || s["status"] == "nodisk" }
      occupied_serials = occupied_slots.map { |s| s["serial"] }.compact

      disks = []
      data.each do |serial, info|
        next if serial.start_with?("_")  # skip _date_time and other metadata keys
        next unless info.is_a?(Hash)

        # A disk is present if ustorage reports at least one occupied slot.
        # When ustorage has no serial data we fall back to checking whether
        # any slot is occupied at all.
        present = if occupied_serials.any?
                    occupied_serials.include?(serial)
                  else
                    occupied_slots.any?
                  end

        disks << AttachedDisk.new(
          serial:          serial,
          model:           info["model_name"],
          size_bytes:      nil,
          slot:            nil,
          power_on_hours:  info["poweronhrs"],
          temperature_c:   info["temperature"],
          life_pct:        info["life_span"],
          bad_sectors:     info["bad_sector"],
          error_log_count: info["error_log_count"],
          present:         present,
          snapshot_date:   snapshot_date
        )
      end

      # Enrich present disks with size from ustorage debug dump
      slot_sizes = parse_ustorage_disk_sizes
      disks.each do |disk|
        match = slot_sizes.find { |s| s[:size] > 0 }
        if match
          disk.size_bytes = match[:size]
          disk.slot       = match[:slot]
        end
      end

      disks
    rescue JSON::ParserError
      []
    end

    def parse_storage_slots
      text = @dump.read("system/storage/ustorage.disk.inspect")
      return [] unless text
      JSON.parse(text)
    rescue JSON::ParserError
      []
    end

    def parse_ustorage_disk_sizes
      text = @dump.read("system/storage/ustorage.debug.dump")
      return [] unless text
      data = JSON.parse(text)
      disks = data.dig("storage", "disks") || {}

      disks.map do |slot, info|
        { slot: slot.to_i, size: info["size"].to_i }
      end
    rescue JSON::ParserError
      []
    end

    def parse_meminfo_field(field)
      text = @dump.read("system/memory/meminfo")
      return nil unless text
      line = text.lines.find { |l| l.start_with?("#{field}:") }
      return nil unless line

      kb = line.split[1].to_i
      kb * 1024
    end

    # df uses human-readable sizes like "9.3G", "974M", "2.0G"
    def parse_df_size(str)
      return 0 if str.nil? || str == "0"

      multipliers = { "K" => 1024, "M" => 1024**2, "G" => 1024**3, "T" => 1024**4 }
      if (m = str.match(/^([\d.]+)([KMGT])$/i))
        (m[1].to_f * multipliers[m[2].upcase]).to_i
      else
        str.to_i
      end
    end
  end
end
