#!/bin/bash

for file in ./projects/11/**/*.jack; do
  echo "Comparing $file"
  ./projects/11/compare.sh $file
done
