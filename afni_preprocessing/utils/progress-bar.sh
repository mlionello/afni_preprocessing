#!/usr/bin/bash

progress-bar() {
  local duration
  local elapsed
  local columns
  local space_available
  local fit_to_screen
  local space_reserved

  space_reserved=6   # reserved width for the percentage value
  max_columns=70
  duration=${1}
  elapsed=${2}
  columns=$(tput cols)
  num_cols=$(( max_columns < columns ? max_columns : columns ))
  num_cols=$(( num_cols-space_reserved ))

  past_space=$((num_cols*elapsed/duration))
  todo_space=$((num_cols-past_space))
  already_done() { printf "( "; for ((done=0; done<past_space ; done=done+1 )); do printf "▇"; done }
  remaining() { for (( remain=past_space ; remain<num_cols-1 ; remain=remain+1 )); do printf "."; done }
  percentage() { printf " ) %s%%" $(( (elapsed)*100/(duration)*100/100 )); }

  if [ 30 -gt $columns ];
  then
  percentage;
  else
  already_done; remaining; percentage
  fi
}
