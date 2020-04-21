for f in **/*.jack; do echo "Filename: $f"; diff -Buw <(./projects/10/vmparser.rb $f | sed -e 's/></>\n</g') $(dirname $f)/$(basename $f .jack).xml; done 2>&1 | less
