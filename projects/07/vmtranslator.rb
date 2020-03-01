#!/usr/bin/env ruby

class VMParser
  attr_accessor :lines, :commands

  def initialize(filename)
    @lines = File.readlines(filename)
    @commands = @lines.map(&VMCommand.method(:create))
  end
end

class VMCommand
  attr_accessor :line

  def initialize(line)
    @line = line
  end

  def to_hack_no_whitespace
    to_hack.split("\n").map(&:strip).reject(&:empty?).join("\n")
  end

  def to_hack
    raise "Not implemented!!"
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

    def create(line)
      (code = line.split('//').first || "").strip!
      command_types.find { |cls| cls.matches?(code) }.new(code)
    end
  end
end

class BinaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      // START OF #{self}
      @SP
      M=M-1     // SP--

      @SP
      A=M
      D=M       // D=*SP

      @SP       // SP--
      M=M-1

      @SP
      A=M
      M=D#{operator}M   // *SP=D+*SP

      @SP               // SP++
      M=M+1
      // START OF #{self}
    HACK
  end
end

class UnaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      // START OF #{self}
      @SP
      M=M-1     // SP--

      @SP
      A=M
      M=#{operator}M   // *SP=!*SP

      @SP               // SP++
      M=M+1
      // END OF #{self}
    HACK
  end
end

class AddCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'add'
  end

  def operator
    ?+
  end
end

class SubCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'sub'
  end

  def operator
    # TODO: order?
    ?-
  end

  def to_hack
    <<-HACK
      // START OF #{self}
      @SP
      M=M-1     // SP--

      @SP
      A=M
      D=M       // D=*SP

      @SP       // SP--
      M=M-1

      @SP
      A=M
      D=-D
      M=D+M   // *SP=D+*SP

      @SP               // SP++
      M=M+1
      // START OF #{self}
    HACK
  end
end

class AndCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'and'
  end

  def operator
    ?&
  end
end

class OrCommand < BinaryOperatorCommand
  def self.matches?(line)
    line == 'or'
  end

  def operator
    ?|
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

  def initialize(line)
    @address = (@@address += 1)
    super
  end

  def self.matches?(line)
    line == 'eq'
  end

  def jump_instruction
    'JEQ'
  end

  def to_hack
    <<-HACK
      // START OF #{self}
      @SP
      M=M-1     // SP--

      @SP
      A=M
      D=M       // D=*SP

      @SP       // SP--
      M=M-1

      @SP
      A=M
      //M=-M    // negate M
      D=-D
      D=D+M   // *SP=*SP+D

      @TRUE#@address
      D;#{jump_instruction}

      @FALSE#@address
      0;JMP

      (TRUE#@address)
        @SP            // *SP=-1
        A=M
        M=0
        M=!M
        @END#@address
        0;JMP
      (FALSE#@address)
        @SP             // *SP=0
        A=M
        M=0
        @END#@address
        0;JMP
      (END#@address)

      @SP               // SP++
      M=M+1
      // END OF #{self}
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
  def self.matches?(line)
    line.start_with?('push')
  end

  def to_hack
    _, segment, index = @line.split(' ')

    if segment == 'constant'
      # sp = &sp + 1
      # *sp = segment[index]
      return <<-HACK
        // START OF PUSH
        @#{index}
        D=A

        @SP
        A=M
        M=D

        @SP
        M=M+1
        // END OF PUSH
      HACK
    end

    <<-HACK
      @#{segment.upcase}
      A=A+#{index}
    HACK
  end
end

class PopCommand < VMCommand
  def self.matches?(line)
    line.start_with?('pop')
  end
end

class NoOpCommand < VMCommand
  # represents comments and empty lines
  def to_hack
    ""
  end

  def self.matches?(line)
    true
  end
end

class VMCodeWriter
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
