#!/bin/bash

source toprint.sh

nocl=1
for i in {0..12}; do
	for j in {0..3}; do
		sleep 2s; toprint HELLO "$i" "$j" - 12 3 - "$nocl"
		nocl=0
done; done
