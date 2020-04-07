#!/usr/bin/env ruby

class JackTokenizer
  attr_accessor :tokens

  def initialize(filename)
    @@seq = 1
    @@found_literal = false
    contents = IO.read(filename)
    @tokens = tokenize(contents)
  end

  def to_xml
    <<-XML
      <tokens>
        #{@tokens.map(&:to_xml) * "\n"}
      </tokens>
    XML
  end

  def chartype(char)
    # TODO how come flipflop doesn't work?
    if @@found_literal || char == '"'
      @@found_literal = !@@found_literal if char == '"'
      return :string_const
    end
    case char
      when /[a-zA-Z0-9]/ then :alphanumeric
      when /\s/ then :whitespace
      else next_seq # hack because we don't want to chunk symbols together
    end
  end

  def next_seq
    @@seq += 1
  end

  def tokenize(contents)
    tokens = strip_excess_whitespace_and_comments(contents)
    tokens = tokens.chars.chunk(&method(:chartype))
    tokens = tokens.map { |x| Token.build(x.first, x.last * '') }
    tokens.reject { |c| c.name == :whitespace }
  end

  def strip_excess_whitespace_and_comments(str)
    str.gsub(/\/\*.*?\*\//m, '')
       .gsub(/\/\/.*?\n/, '')
       .gsub(/\n/, '')
       .gsub(/\r/, '')
       .gsub(/\s+/, ' ')
  end
end

class Token
  attr_accessor :name, :value, :escaped_value

  def initialize(name, value)
    @name, @value = name, value
    @escaped_value = escape_value(value)
  end

  def self.keyword?(str)
    keywords = %w[ class method function constructor int boolean char void var static field let do if else while return true false null this ]
    keywords.include?(str.downcase)
  end

  def self.build(name, value)
    xml_name = case
      when name.is_a?(Numeric) then :symbol
      when keyword?(value) then :keyword
      when name == :alphanumeric && value =~ /^[0-9]+$/ then :integerConstant
      when name == :alphanumeric then :identifier
      when name == :string_const then :stringConstant
      when name == :whitespace then name
      else :symbol
    end
    new(xml_name, value)
  end

  def escape_value(val)
    escape_char_xref = {
      '>' => '&gt;',
      '<' => '&lt;',
      '"' => '&quot;',
      '&' => '&amp;',
    }
    remove_quotes_maybe(escape_char_xref[val] || val)
  end

  def remove_quotes_maybe(val)
    if @name == :string_const
      val.tr('"', '')
    else
      val
    end
  end

  def to_xml
    "<#@name> #@escaped_value </#@name>"
  end
end

class CompilationEngine
  class << self
    def compile(tokens)
    end
  end
end

class JackAnalyzer
  def self.analyze(path_or_file)
    path = path_or_file + (path_or_file.include?(?.) ? '' : '*.jack')
    files = Dir[path]

    files.each do |filepath|
      tokenizer = JackTokenizer.new(filepath)
      puts tokenizer.to_xml
      #output = CompilationEngine.compile(tokenizer.tokens)
      #outputfile = filepath.gsub('.jack', '.xml')

      #open(outputfile, 'w') do |f|
      #  f.puts output.join('\n')
      #end
    end
  end
end

JackAnalyzer.analyze(ARGV.first)
