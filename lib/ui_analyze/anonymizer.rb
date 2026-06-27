# frozen_string_literal: true

module UiAnalyze
  # Replaces identifying values with stable, deterministic placeholders.
  # Each unique value gets the same placeholder within a session.
  class Anonymizer
    MAC_RE     = /\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/
    UUID_RE    = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i
    SERIAL_RE  = /\b[A-Z0-9]{10,20}\b/

    def initialize
      @counters = Hash.new(0)
      @map = {}
    end

    def serial(v)    = redact(v, "SERIAL")
    def mac(v)       = redact(v, "MAC")
    def uuid(v)      = redact(v, "UUID")
    def qr_id(v)     = redact(v, "QRID")
    def anon_id(v)   = redact(v, "ANONID")
    def hash_id(v)   = redact(v, "HASHID")
    def bom(v)       = redact(v, "BOM")
    def board_rev(v) = redact(v, "BOARDREV")
    def hostname(v)  = redact(v, "HOST")

    # Redact from a firmware string only the hex commit hash (e.g. "3fbc1da")
    # while preserving the version number and date.
    def firmware(v)
      return v unless v
      v.gsub(/\.[0-9a-f]{7,}\.\d{6}\./) { |m|
        parts = m.split(".")
        # parts: ["", hexhash, datepart, ""]
        ".#{redact(parts[1], "COMMIT")}.#{parts[2]}."
      }
    end

    # Replace any MAC addresses, UUIDs, long uppercase hex serials, or firmware
    # version strings found inline in an arbitrary string.
    def scrub(v)
      return v unless v
      v = firmware(v)
      v = v.gsub(MAC_RE)    { redact($&, "MAC") }
      v = v.gsub(UUID_RE)   { redact($&, "UUID") }
      v = v.gsub(SERIAL_RE) { redact($&, "SERIAL") }
      v
    end

    private

    def redact(v, prefix)
      return v unless v
      @map[v] ||= begin
        @counters[prefix] += 1
        n = @counters[prefix]
        n == 1 ? "<#{prefix}>" : "<#{prefix}#{n}>"
      end
    end
  end
end
