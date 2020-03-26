filename="$1"
tst_filename="${$filename/.asm/.tst}"

echo "tst_filename is $tst_filename"

ruby projects/08/vmtranslator.rb $filename

./tools/CPUEmulator.sh $x
