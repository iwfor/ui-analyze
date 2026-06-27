# ui-analyze

A command-line tool for analyzing UniFi support dump tarballs. Reports device
identity, hardware specs, storage, and boot history with per-firmware crash rate
analysis.

## Usage

```
ui-analyze [options] <path-to-support-dump>
```

The path can be either an extracted support dump directory or a `.tar.gz`
tarball — the tool handles both.

### Options

| Flag | Description |
|---|---|
| `--from DATE` | Only show boots on or after `DATE` (YYYY-MM-DD) |
| `--to DATE` | Only show boots on or before `DATE` (YYYY-MM-DD) |
| `-h, --help` | Show usage |

### Examples

```bash
# Analyze an extracted support dump
ruby bin/ui-analyze ~/Downloads/support-DD71-1782218420499

# Analyze a tarball directly
ruby bin/ui-analyze ~/Downloads/support-DD71-1782218420499.tar.gz

# Show only June 2026
ruby bin/ui-analyze --from 2026-06-01 --to 2026-06-30 ~/Downloads/support-DD71-1782218420499

# Show everything from a date onward
ruby bin/ui-analyze --from 2026-03-22 ~/Downloads/support-DD71-1782218420499
```

## Output

### Device Information
Identity fields parsed from `system/system-id.txt` and `system/kernel/ubnthal.system.info`:
name, model, serial, MAC address, QR ID, UUID, BOM, board revision, and hostname.

### Hardware Specs
CPU model, RAM, and flash size.

### Firmware
Current firmware version and manufacturing week.

### Storage
- **Attached disks** — model, serial, health %, temperature, power-on hours, bad
  sectors, and error log count from SMART data. Disks that appear in historical
  logs but are no longer installed are flagged with a warning and the date they
  were last seen.
- **Filesystem table** — size, used, available, and use% for all real block
  devices. Partitions at ≥90% use are highlighted red; ≥75% yellow.
- **Swap** — total, used, and free.

### Boot History
Chronological table of every boot with timestamp, uptime since the previous
boot, firmware version, and reboot reason. Empty boot logs (indicating the
system crashed before the bootloader could write the log) are flagged with ⚠.

Reboot reasons:
- 🔴 **Improper shutdown** — the system crashed or was reset without a clean shutdown
- 🔵 **Firmware upgrade** — intentional reboot as part of a firmware update
- 🟢 **Normal reboot** — clean operator-initiated reboot
- 🟡 **Factory reset**

### Reboot Rate by Firmware
Summarizes the number of improper shutdowns and average time between crashes for
each firmware version active during the dump's history window. When `--from`/`--to`
are used, the table reflects only the filtered period.

## Requirements

Ruby 3.x, no gems required.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
