find projects/08/ -name '*.vm' | xargs -I {} ruby projects/08/vmtranslator.rb {}

for x in $(find projects/08/ -name '*.tst' | grep -v VM); do ./tools/CPUEmulator.sh $x; done
