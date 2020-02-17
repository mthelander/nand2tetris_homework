#!/usr/bin/env ruby

class Parser
  attr_accessor :lines, :commands

  def initialize(filename)
    @lines = File.open(filename).readlines
    @commands = @lines.map { |line| Command.new(line) }
  end
end

class Command
  attr_accessor :line

  def initialize(line)
    @line = line.split('//').first || ""
    @line.strip!
  end

  def command_type
    case @line[0]
      when ?@ then :a_command
      when ?( then :l_command
      when ?/ then :comment
      when nil then :comment
      else :c_command
    end
  end

  def is_comment?
    command_type == :comment
  end

  def c_command?
    command_type == :c_command
  end

  def a_command?
    command_type == :a_command
  end

  def l_command?
    command_type == :l_command
  end

  def symbol
    if a_command?
      @line[1..-1]
    elsif l_command?
      @line[1..-2]
    end
  end

  def dest
    if c_command? && @line.include?(?=)
      @line.split(?=).first
    end
  end

  def comp
    if c_command?
      right = @line.split(?=).last
      val = right.split(?;).first
      val.empty? ? nil : val
    end
  end

  def jump
    if c_command?
      if @line.include?(?;)
        @line.split(?;).last
      end
    end
  end

  def binary_code
    code = Code.new # TODO: combine Code with Command

    val = if c_command?
      parts = [
        "111",
        code.comp(comp),
        code.dest(dest),
        code.jump(jump),
      ]
      parts.join
    elsif a_command?
      symbol.to_i.to_s(2)
    end

    val.rjust(16, ?0) unless val.nil?
  end
end

class Code
  def dest(mnemonic)
    return "000" if mnemonic.nil?
    xref = {
      "M"   => "001",
      "D"   => "010",
      "DM"  => "011",
      "A"   => "100",
      "AM"  => "101",
      "AD"  => "110",
      "ADM" => "111",
    }

    key = mnemonic.chars.sort.join
    xref[key]
  end

  def jump(mnemonic)
    return "000" if mnemonic.nil?
    xref = {
      "JGT" => "001",
      "JEQ" => "010",
      "JGE" => "011",
      "JLT" => "100",
      "JNE" => "101",
      "JLE" => "110",
      "JMP" => "111",
    }
    xref[mnemonic]
  end

  def comp(mnemonic)
    xref = {
      "0"   => "0101010",
      "1"   => "0111111",
      "-1"  => "0111010",
      "D"   => "0001100",
      "A"   => "0110000",
      "M"   => "1110000",
      "!D"  => "0001101",
      "!A"  => "0110001",
      "!M"  => "1110001",
      "-D"  => "0001111",
      "-A"  => "0110011",
      "-M"  => "1110011",
      "D+1" => "0011111",
      "1+D" => "0011111", # reversed
      "A+1" => "0110111",
      "1+A" => "0110111", # reversed
      "M+1" => "1110111",
      "1+M" => "1110111", # reversed
      "D-1" => "0001110",
      "A-1" => "0110010",
      "M-1" => "1110010",
      "D+A" => "0000010",
      "A+D" => "0000010", # reversed
      "D+M" => "1000010",
      "M+D" => "1000010", # reversed
      "D-A" => "0010011",
      "D-M" => "1010011",
      "A-D" => "0000111",
      "M-D" => "1000111",
      "D&A" => "0000000",
      "A&D" => "0000000", # reversed
      "D&M" => "1000000",
      "M&D" => "1000000", # reversed
      "D|A" => "0010101",
      "A|D" => "0010101", # reversed
      "D|M" => "1010101",
      "M|D" => "1010101", # reversed
    }
    xref[mnemonic]
  end
end

def main(filename)
  parser = Parser.new(filename)
  code = Code.new
  binaries = []
  output_filename = filename.gsub('.asm', '.hack')

  parser.commands.reject(&:is_comment?).each do |command|
    val = command.binary_code
    binaries << val unless val.nil?
  end

  File.open(output_filename, "w") do |fh|
    fh.puts binaries
  end
end

main(ARGV.first)
