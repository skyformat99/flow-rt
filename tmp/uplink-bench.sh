#!/bin/bash

function bench {
	echo $1;
	for x in 1 2 4 5 6 7 8 9 10 11 12
	do
		printf "$((1000*x))\t"
		echo "import std.meta, std.range; static immutable x = aliasSeqOf!(iota($((1000*x))));" > uplink.d
		db=$(date +"%s%N")
		ldc2 -c uplink.d
		de=$(date +"%s%N")
		echo $(expr $de - $db)
	done
}

bench "dmd";
bench "ldc2";
