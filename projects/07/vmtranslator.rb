#!/usr/bin/env ruby

class VMParser
  attr_accessor :lines, :commands

  def initialize(filename)
    @lines = File.readlines(filename)
    @commands = @lines.map { |line| VMCommand.create(line, filename) }
  end
end

class VMCommand
  attr_accessor :line, :filename

  def initialize(line, filename)
    @line, @filename = line, filename
  end

  def to_hack_no_whitespace
    to_hack.split("\n").map(&:strip).reject(&:empty?).join("\n")
  end

  def to_hack
    ""
  end

  class << self
    def command_types
      return [
        AddCommand,
        SubCommand,
        EqCommand,
        GtCommand,
        LtCommand,
        AndCommand,
        OrCommand,
        NegCommand,
        NotCommand,
        PushCommand,
        PopCommand,
        NoOpCommand,
      ]
    end

    def create(line, filename)
      (code = line.split('//').first || "").strip!
      command_types.find { |cls| cls.matches?(code) }.new(code, filename)
    end
  end
end

class BinaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      @SP
      M=M-1

      @SP
      A=M
      D=M

      @SP
      M=M-1

      @SP
      A=M
      #{operator_code}

      @SP
      M=M+1
    HACK
  end

  def operator_code
    'M=D-M'
  end
end

class UnaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      @SP
      M=M-1

      @SP
      A=M
      M=#{operator}M

      @SP
      M=M+1
    HACK
  end
end

class AddCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'add'
  end

  def operator_code
    'M=D+M'
  end
end

class SubCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'sub'
  end

  def operator_code
    <<-HACK
      D=-D
      M=D+M
    HACK
  end
end

class AndCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'and'
  end

  def operator_code
    'M=D&M'
  end
end

class OrCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'or'
  end

  def operator_code
    'M=D|M'
  end
end

class NegCommand < UnaryOperatorCommand
  def self.matches?(line)
    line == 'neg'
  end

  def operator
    ?-
  end
end

class NotCommand < UnaryOperatorCommand
  def self.matches?(line)
    line == 'not'
  end

  def operator
    ?!
  end
end

class EqCommand < BinaryOperatorCommand
  @@address = 0

  def initialize(line, filename)
    @address = (@@address += 1)
    super
  end

  def self.matches?(line)
    line == 'eq'
  end

  def jump_instruction
    'JEQ'
  end

  def operator_code
    <<-HACK
      D=-D
      D=D+M

      @TRUE#@address
      D;#{jump_instruction}

      @FALSE#@address
      0;JMP

      (TRUE#@address)
        @SP
        A=M
        M=0
        M=!M
        @END#@address
        0;JMP
      (FALSE#@address)
        @SP
        A=M
        M=0
        @END#@address
        0;JMP
      (END#@address)
    HACK
  end
end

class GtCommand < EqCommand
  def self.matches?(line)
    line == 'gt'
  end

  def jump_instruction
    'JGT'
  end
end

class LtCommand < EqCommand
  def self.matches?(line)
    line == 'lt'
  end

  def jump_instruction
    'JLT'
  end
end

class PushCommand < VMCommand
  TEMP_ADDRESS = 5

  def self.matches?(line)
    line.start_with?('push')
  end

  def get_pointer_symbol(segment, index)
    case
      when segment == 'temp' then TEMP_ADDRESS + index
      when index == 0 then 'THIS'
      when segment == 'static' then [ File.basename(@filename, ".*"), index ] * ?.
      else'THAT'
    end
  end

  def symbol_map
    @symbol_map ||= {
      'local'    => 'LCL',
      'this'     => 'THIS',
      'that'     => 'THAT',
      'argument' => 'ARG',
    }
  end

  def to_hack
    _, segment, index_str = @line.split(' ')
    index = index_str.to_i
    offset_modifier = (['A=A+1'] * index) * "\n"

    arg_hack = case segment
      when 'constant'
        <<-HACK
          @#{index}
          D=A
        HACK
      when 'local', 'this', 'that', 'argument'
        symbol = symbol_map[segment] or raise "Invalid segment: #{segment}"
        <<-HACK
          @#{symbol}
          A=M
          #{offset_modifier}
          D=M
        HACK
      when 'temp', 'pointer', 'static'
        <<-HACK
          @#{get_pointer_symbol(segment, index)}
          D=M
        HACK
    end

    return <<-HACK
      #{arg_hack}
      @SP
      A=M
      M=D
      @SP
      M=M+1
    HACK
  end
end

class PopCommand < PushCommand
  def self.matches?(line)
    line.start_with?('pop')
  end

  def to_hack
    _, segment, index_str = @line.split(' ')
    index = index_str.to_i
    offset_modifier = (['A=A+1'] * index) * "\n"

    arg_hack = case segment
      when 'local', 'this', 'that', 'argument'
        symbol = symbol_map[segment] or raise "Invalid segment: #{segment}"
        <<-HACK
          @#{symbol}
          A=M
          #{offset_modifier}
          M=D
        HACK
      when 'temp', 'pointer', 'static'
        <<-HACK
          @#{get_pointer_symbol(segment, index)}
          M=D
        HACK
    end

    return <<-HACK
      @SP
      M=M-1
      A=M
      D=M
      #{arg_hack}
    HACK
  end
end

class NoOpCommand < VMCommand
  def self.matches?(line)
    true
  end
end

def main(file)
  path = file + (file.include?(?.) ? '' : '*.vm')
  files = Dir[path]
  parsers = files.map { |f| VMParser.new(f) }
  outputfile = files[0].gsub('.vm', '.asm')

  codes = parsers.map do |parser|
    parser.commands.map(&:to_hack_no_whitespace).reject(&:empty?).join("\n")
  end

  open(outputfile, 'w') do |f|
    f.puts codes.join("\n")
  end
end

main(ARGV.first)
