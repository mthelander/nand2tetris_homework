find projects/07/ -name '*.vm' | xargs -I {} ruby projects/07/vmtranslator.rb {}

for x in $(find projects/07/ -name '*.tst' | grep -v VM); do ./tools/CPUEmulator.sh $x; done
