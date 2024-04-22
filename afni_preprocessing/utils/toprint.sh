#!/usr/bin/bash

function toprint {
script_path=$(dirname "$(readlink -f "$0")")
source "$script_path"/progress-bar.sh

nameproc=$1
step=$2
subj_i=$3
run_i=$4
tot_steps=$5
tot_subjs=$6
tot_runs=$7
no_cl=$8

UPLINE=$(tput cuu1)
ERASELINE=$(tput el)

clear_all() { printf "$UPLINE$ERASELINE$UPLINE$ERASELINE$UPLINE"; }

print_fline() { printf "\033[2K\rsubject: $subj_i/$tot_subjs, run $run_i/$tot_runs\n"; }
print_sline() { printf "\n\033[2K\r$nameproc... $step/$tot_steps\n"; }

if [[ ! "$no_cl" -eq 1 ]]; then
clear_all;
fi
print_fline;
progress-bar "$tot_subjs" "$subj_i";
print_sline;
progress-bar "$tot_steps" "$step";
}

