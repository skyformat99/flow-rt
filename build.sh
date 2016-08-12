#!/bin/bash

function build() {
	cd $1
	#dub build #--compiler=ldc2
	dub test #--compiler=ldc2
	cd ..
}

#build thrift
build flowbase
#build playground

