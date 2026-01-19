# frozen_string_literal: true

module BranchEnv
  class PortRegistry
    def initialize(dry_run: false)
      @dry_run = dry_run
      @state_dir = File.join(BranchEnv::ROOT, "state")
      @registry_path = File.join(@state_dir, "ports.tsv")
      @lock_path = File.join(@state_dir, "ports.lock")

      FileUtils.mkdir_p(@state_dir)
      FileUtils.touch(@registry_path) unless File.exist?(@registry_path)
    end

    def get(key)
      entries[key]
    end

    def allocate(key, range)
      with_lock do
        existing = get(key)
        return existing if existing

        port = range.find { |p| !port_taken?(p) && !port_in_use?(p) }
        raise Error, "No free port available in range #{range}" unless port

        # Call internal version without lock (we already hold it)
        do_register(key, port)
        port
      end
    end

    def register(key, port)
      with_lock do
        do_register(key, port)
      end
      port
    end

    def remove(key)
      with_lock do
        current = entries
        port = current.delete(key)
        write_entries(current)
        port
      end
    end

    def entries
      return {} unless File.exist?(@registry_path)

      File.readlines(@registry_path).each_with_object({}) do |line, hash|
        key, port = line.strip.split("\t")
        hash[key] = port.to_i if key && port
      end
    end

    def all_for_project(project_key)
      entries.select { |key, _| key.start_with?("#{project_key}:") }
    end

    private

    def do_register(key, port)
      current = entries
      current[key] = port
      write_entries(current)
    end

    def port_taken?(port)
      entries.values.include?(port)
    end

    def port_in_use?(port)
      # Check if something is actually listening on the port
      system("lsof -nP -iTCP:#{port} -sTCP:LISTEN >/dev/null 2>&1")
    end

    def write_entries(hash)
      return if @dry_run

      content = hash.map { |k, v| "#{k}\t#{v}" }.join("\n")
      content += "\n" unless content.empty?
      File.write(@registry_path, content)
    end

    def with_lock(&block)
      File.open(@lock_path, File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        result = block.call
        f.flock(File::LOCK_UN)
        result
      end
    end
  end
end
