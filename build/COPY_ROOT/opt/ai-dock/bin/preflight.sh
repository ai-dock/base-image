#!/bin/bash

# Extended image should have preflight.sh in $PATH before this one to modify startup behavior

function main() {
    do_something
}

function do_something() {
    printf "Empty preflight.sh...\n"
}

main "$@"; exit