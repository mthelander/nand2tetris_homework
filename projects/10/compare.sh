#!/bin/bash

file=$1
diff -Buw <(./projects/10/vmanalyze.rb $file | sed -e 's/></>\n</g') "$(dirname $file)/$(basename $file .jack).xml"
