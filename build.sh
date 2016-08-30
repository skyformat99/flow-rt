#!/bin/bash

rootDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $rootDir/base && dub test &&
cd $rootDir/util && dub test &&
cd $rootDir/alien && dub test &&

cd $rootDir/causal && dub build --build $1 ${@:2}
