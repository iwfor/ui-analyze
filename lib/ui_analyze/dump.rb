# frozen_string_literal: true

require "tmpdir"
require "open3"

module UiAnalyze
  # Represents a support dump — either an extracted directory or a tarball.
  # Provides a unified #read(path) interface regardless of source format.
  class Dump
    attr_reader :root

    def self.open(path, &block)
      new(path).tap { |d| d.send(:setup) }.then do |dump|
        block ? block.call(dump) : dump
      end
    end

    def initialize(path)
      @path = File.expand_path(path)
      @tmpdir = nil
    end

    def read(relative_path)
      full = File.join(@root, relative_path)
      return nil unless File.file?(full)

      File.read(full)
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def glob(pattern)
      Dir.glob(File.join(@root, pattern)).map do |f|
        f.delete_prefix(@root + "/")
      end
    end

    def cleanup
      FileUtils.rm_rf(@tmpdir) if @tmpdir
    end

    private

    def setup
      if File.directory?(@path)
        # Already extracted — find the actual support dump root
        # (could be the path itself, or one level down if it's a wrapper dir)
        @root = find_dump_root(@path)
      elsif @path.match?(/\.(tar\.gz|tgz)$/)
        extract_tarball
      else
        raise ArgumentError, "Unsupported format: #{@path}. Expected a directory or .tar.gz file."
      end
    end

    def find_dump_root(dir)
      # The dump root contains a "system" subdirectory
      return dir if File.directory?(File.join(dir, "system"))

      candidate = Dir.glob(File.join(dir, "*/system")).first
      candidate ? File.dirname(candidate) : dir
    end

    def extract_tarball
      @tmpdir = Dir.mktmpdir("ui-analyze-")
      out, err, status = Open3.capture3("tar", "-xzf", @path, "-C", @tmpdir)
      unless status.success?
        FileUtils.rm_rf(@tmpdir)
        raise "Failed to extract #{@path}: #{err}"
      end
      @root = find_dump_root(@tmpdir)
    end
  end
end
