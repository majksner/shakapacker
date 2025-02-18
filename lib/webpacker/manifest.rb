# Singleton registry for accessing the packs path using a generated manifest.
# This allows javascript_pack_tag, stylesheet_pack_tag, asset_pack_path to take a reference to,
# say, "calendar.js" or "calendar.css" and turn it into "/packs/calendar-1016838bab065ae1e314.js" or
# "/packs/calendar-1016838bab065ae1e314.css".
#
# When the configuration is set to on-demand compilation, with the `compile: true` option in
# the webpacker.yml file, any lookups will be preceded by a compilation if one is needed.
class Webpacker::Manifest
  class MissingEntryError < StandardError; end

  delegate :config, :compiler, :dev_server, to: :@webpacker

  def initialize(webpacker)
    @webpacker = webpacker
  end

  def refresh
    @data = load
  end

  def lookup_pack_with_chunks(name, pack_type = {})
    compile if compiling?

    manifest_pack_type = manifest_type(pack_type[:type])
    manifest_pack_name = manifest_name(name, manifest_pack_type)
    find("entrypoints")[manifest_pack_name]["assets"][manifest_pack_type]
  rescue NoMethodError
    nil
  end

  def lookup_pack_with_chunks!(name, pack_type = {})
    lookup_pack_with_chunks(name, pack_type) || handle_missing_entry(name, pack_type)
  end

  # Computes the relative path for a given Webpacker asset using manifest.json.
  # If no asset is found, returns nil.
  #
  # Example:
  #
  #   Webpacker.manifest.lookup('calendar.js') # => "/packs/calendar-1016838bab065ae1e122.js"
  def lookup(name, pack_type = {})
    compile if compiling?

    find(full_pack_name(name, pack_type[:type]))
  end

  # Like lookup, except that if no asset is found, raises a Webpacker::Manifest::MissingEntryError.
  def lookup!(name, pack_type = {})
    lookup(name, pack_type) || handle_missing_entry(name, pack_type)
  end

  private
    def compiling?
      config.compile? && !dev_server.running?
    end

    def compile
      Webpacker.logger.tagged("Webpacker") { compiler.compile }
    end

    def data
      if config.cache_manifest?
        @data ||= load
      else
        refresh
      end
    end

    def find(name)
      data[name.to_s].presence
    end

    def full_pack_name(name, pack_type)
      return name unless File.extname(name.to_s).empty?
      "#{name}.#{manifest_type(pack_type)}"
    end

    def handle_missing_entry(name, pack_type)
      raise Webpacker::Manifest::MissingEntryError, missing_file_from_manifest_error(full_pack_name(name, pack_type[:type]))
    end

    def load
      if config.manifest_path.exist?
        JSON.parse config.manifest_path.read
      else
        {}
      end
    end

    # The `manifest_name` method strips of the file extension of the name, because in the
    # manifest hash the entrypoints are defined by their pack name without the extension.
    # When the user provides a name with a file extension, we want to try to strip it off.
    def manifest_name(name, pack_type)
      name.chomp(".#{pack_type}")
    end

    def manifest_type(pack_type)
      case pack_type
      when :javascript then "js"
      when :stylesheet then "css"
      else pack_type.to_s
      end
    end

    def missing_file_from_manifest_error(bundle_name)
      <<-MSG
Webpacker can't find #{bundle_name} in #{config.manifest_path}. Possible causes:
1. You forgot to install node packages (try `yarn install`) or are running an incompatible version of Node
2. Your app has code with a non-standard extension (like a `.jsx` file) but the extension is not in the `extensions` config in `config/webpacker.yml`
3. You have set compile: false (see `config/webpacker.yml`) for this environment
   (unless you are using the `bin/webpacker -w` or the `bin/webpacker-dev-server`, in which case maybe you aren't running the dev server in the background?)
4. webpack has not yet re-run to reflect updates.
5. You have misconfigured Webpacker's `config/webpacker.yml` file.
6. Your webpack configuration is not creating a manifest.

Your manifest contains:
#{JSON.pretty_generate(@data)}
      MSG
    end
end
