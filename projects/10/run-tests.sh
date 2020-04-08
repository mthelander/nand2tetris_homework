#!/bin/bash

for file in $(find . -name "*T.xml"); do
  jack=$(echo "$file" | sed 's/T.xml/.jack/')
  echo "COMPARING $file; $jack"
  gen=$(ruby projects/10/vmanalyze.rb "$jack")
  diff -w <( ruby projects/10/vmanalyze.rb "$jack" ) "$file"
done
