#
# Web frameworks often require a set of JavaScript and/or CSS stylesheet files
# to be pulled in.  Asset support makes it easy to deploy such files to be
# deployed statically; and furthermore to automatically insert the relevant
# <script src> or <link rel="stylesheet"> lines to the <head> section of your
# HTML.
#
# For examples, see angularjs.rb, jquery.rb, opal.rb, pagedown.rb, or
# polymer.rb.
#

require 'fileutils'
require 'thread'

module Wunderbar
  class Asset
    class << self
      # URI path prepended to individual asset path
      attr_accessor :path

      # location where the asset directory is to be found/placed
      attr_accessor :root

      # don't fall back to content if file doesn't exist on disk
      attr_accessor :virtual
    end

    # asset file location
    attr_reader :path

    # asset contents
    attr_reader :contents

    # asset modification time
    attr_reader :mtime

    # general options
    attr_reader :options

    def self.clear
      @@scripts = []
      @@stylesheets = []
    end

    def self.content_type_for(path)
      if @@scripts.any? {|script| script.path == path}
        'application/javascript'
      elsif @@stylesheets.any? {|script| script.path == path}
        'text/css'
      else
        'application/octet-stream'
      end
    end

    def self.find(path)
      (@@scripts.find {|script| script.path == path}) ||
        (@@stylesheets.find {|script| script.path == path})
    end

    clear

    env = Thread.current[:env] || ENV

    @path = '../' * env['PATH_INFO'].to_s.count('/') + 'assets'
    @root ||= nil
    @root = File.dirname(env['SCRIPT_FILENAME']) if env['SCRIPT_FILENAME']
    @root = File.expand_path((@root || Dir.pwd) + "/assets").untaint

    # Options: typically :name plus either :file or :contents
    #   :name => name to be used for the asset
    #   :file => source for the asset
    #   :contents => contents of the asset
    def initialize(options)
      @options = options
      source = options[:file] || __FILE__
      @contents = options[:contents]

      options[:name] ||= File.basename(options[:file]) if source

      if options[:name]
        @mtime = File.mtime(source)
        @path = options[:name]
        dest = File.expand_path(@path, Asset.root)

        if not File.exist?(dest) or File.mtime(dest) < @mtime
          begin
            FileUtils.mkdir_p File.dirname(dest)
            if options[:file]
              FileUtils.cp source, dest, :preserve => true
            else
              open(dest, 'w') {|file| file.write @contents}
            end
          rescue
            @path = nil unless Asset.virtual
            @contents ||= File.read(source)
          end
        end
      end
    end

    def self.script(options)
      @@scripts << self.new(options)
    end

    def self.css(options)
      @@stylesheets << self.new(options)
    end

    def self.scripts
      @@scripts
    end

    def self.declarations(root, prefix)
      path = prefix.to_s + Asset.path

      unless @@scripts.empty?
        before = root.at('script')
        if before
          before = before.parent while before.parent and 
            not %w(head body).include? before.parent.name.to_s
        end
        parent = (before ? before.parent : root.at('body')) || root

        nodes = []
        @@scripts.each do |script|
          if script.path
            nodes << Node.new(:script, src: "#{path}/#{script.path}")
          elsif script.contents
            nodes << ScriptNode.new(:script, script.contents)
          end
        end

        nodes.each {|node| node.parent = parent}
        index = parent.children.index(before) || -1
        parent.children.insert(index, *nodes) if before
      end

      unless @@stylesheets.empty?
        before = root.at('link[rel=stylesheet]')
        if before
          before = before.parent while before.parent and 
            not %w(head body).include? before.parent.name.to_s
        end
        parent = (before ? before.parent : root.at('head')) || root

        nodes = []
        @@stylesheets.each do |stylesheet|
          if stylesheet.path
            nodes << Node.new(:link, rel: "stylesheet", type: "text/css",
              href: "#{path}/#{stylesheet.path}")
          elsif stylesheet.contents
            nodes << StyleNode.new(:style, stylesheet.contents)
          end
        end

        nodes.each {|node| node.parent = parent}
        index = parent.children.index(before) || -1
        parent.children.insert(index, *nodes)
      end
    end
  end
end
