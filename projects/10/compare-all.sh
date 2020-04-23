#!/bin/bash

for file in ./projects/10/**/*.jack; do
  echo "Comparing $file"
  ./projects/10/compare.sh $file
done
