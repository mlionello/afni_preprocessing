#!/usr/bin/bash

# Function to display help message
display_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --num_cpus        Number of CPUs (default: 16)"
  echo "  --fwh             Full width at half maximum (default: 4)"
  echo "  --vox_res         Voxel resolution (default: 2)"
  echo "  --tr              Temporal resolution (default: 1)"
  echo "  --data_folder     Path to data folder (default: $data_folder)"
  echo "  --output_folder   Path to output folder (default: $output_folder)"
  echo "  --mnitemp         Path to MNI template (default: $mnitemp)"
  echo "  --onlysubj        Space-separated list of subjects (default: empty)"
  echo "  --skipsubj        Space-separated list of subjects to skip (default: empty)"
  echo "  --compute_anat    Flag to compute anatomical preprocessing (default: 1)"
  echo "  --compute_func    Flag to compute functional preprocessing (default: 1)"
  echo "  --performTShift   Flag for temporal shifting (default: 0)"
  echo "  --ciric           Flag for a ciric-specific option (default: 1)"
  echo "  --deconv_single_run   Flag for deconvolution in a single run (default: 1)"
  echo "  --tasks_regressors   Flag for tasks regressors (default: 1)"
  echo "  --onset_regressor    Flag for onset regressors (default: 1)"
  echo "  --help            Display this help message"
}

# Set script path and source additional script
script_path=$(dirname "$(readlink -f "$0")")
pckg_path=$(dirname "$script_path")
data_path="$pckg_path"/data
source "$script_path"/toprint.sh

# Params
num_cpus=16
fwh=4
vox_res=2
data_folder="$data_path"/shorts/shortest
output_folder="$data_path"/derivatives_new
mnitemp="$data_path"/MNI152_2009_template.nii.gz
onlysubj=() # e.g. ("sub-04" "sub-25")
skipsubj=()
compute_anat=1
compute_func=1
performTShift=0
ciric=1
deconv_single_run=1
tasks_regressors=1
onset_regressor=1
TR=1

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --num_cpus)
      num_cpus=$2
      shift 2
      ;;
    --fwh)
      fwh=$2
      shift 2
      ;;
    --vox_res)
      vox_res=$2
      shift 2
      ;;
    --data_folder)
      data_folder=$2
      shift 2
      ;;
    --output_folder)
      output_folder=$2
      shift 2
      ;;
    --mnitemp)
      mnitemp=$2
      shift 2
      ;;
    --onlysubj)
      IFS=' ' read -ra onlysubj <<< "$2"
      shift 2
      ;;
    --skipsubj)
      IFS=' ' read -ra skipsubj <<< "$2"
      shift 2
      ;;
    --compute_anat)
      compute_anat=$2
      shift 2
      ;;
    --compute_func)
      compute_func=$2
      shift 2
      ;;
    --performTShift)
      performTShift=$2
      shift 2
      ;;
    --ciric)
      ciric=$2
      shift 2
      ;;
    --deconv_single_run)
      deconv_single_run=$2
      shift 2
      ;;
    --tasks_regressors)
      tasks_regressors=$2
      shift 2
      ;;
    --onset_regressor)
      onset_regressor=$2
      shift 2
      ;;
    --tr)
      TR=$2
      shift 2
      ;;
    --help)
      display_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      display_help
      exit 1
      ;;
  esac
done

# Environment Variables
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$num_cpus
export OMP_NUM_THREADS=$num_cpus
export ANTSPATH="$HOME"/ANTS-v2.3.5-126/bin/

tShiftchar="t"
[[ "$performTShift" -eq 0 ]] && tShiftchar=""

# Subject and Run Information
subjs=($(ls -d "$data_folder"/*/ | awk -F/ '{print $(NF-1)}'))
runs=(01 02)

# Check subjects
if [ ${#onlysubj[@]} -ne 0 ] && [ ${#skipsubj[@]} -ne 0 ]; then
  for elem in "${skipsubj[@]}"; do
    if [[ " ${onlysubj[@]} " =~ " $elem " ]]; then
      echo "Error: skip subjects and only subjects cannot contain the same element. Exiting..."
      exit 1
    fi
  done
fi

if [[ ${#onlysubj[@]} -ne 0 ]]; then
  for element in "${onlysubj[@]}"; do
    if [[ ! " ${subjs[@]} " =~ " $element " ]]; then
      echo "Error: The onlysubj set contains participant ids not present in the data folder."
      exit 1
    fi
  done
fi

if [[ ${#skipsubj[@]} -ne 0 ]]; then
  for element in "${skipsubj[@]}"; do
    if [[ ! " ${subjs[@]} " =~ " $element " ]]; then
      echo "Error: The skipsubj set contains participant ids not present in data folder."
      exit 1
    fi
  done
fi

[[ ! ${#onlysubj[@]} -eq 0 ]] && subjs=("${onlysubj[@]}")

if [[ ! ${#skipsubj[@]} -eq 0 ]]; then
  for elem in ${skipsubj[@]}; do
    for i in ${!subjs[@]}; do
      if [ "${subjs[$i]}" == "$elem" ]; then
          unset subjs[$i]
      fi
    done
  done
fi

subjs=("${subjs[@]}")
num_subjs="${#subjs[@]}"
num_runs="${#runs[@]}"
current_file_stem=$(echo "$0" | awk -F"/" '{print $NF}' | sed 's/\.[^.]*$//')
cp "$0" "${output_folder}/${current_file_stem}_$(date +"%Y%m%d_%H%M%S").sh"

# Call anatomical preprocessing script
if [[ "$compute_anat" -eq 1 ]]; then
  "$script_path"/anatomical_preprocessing.sh "$data_folder" "$output_folder" "$num_cpus" "$subjs" \
    "$mnitemp" "$ciric" "$num_subjs" "${subjs[@]}"
fi

# Call functional preprocessing script
if [[ "$compute_func" -eq 1 ]]; then
  "$script_path"/functional_preprocessing.sh "$data_folder" "$output_folder" "$num_cpus" "$compute_func" \
    "$performTShift" "$tShiftchar" "$vox_res" "$fwh" "$mnitemp" "$ciric" "$deconv_single_run" "$tasks_regressors" \
    "$onset_regressor" "$TR" "$num_subjs" "$num_runs" "${subjs[@]}" "${runs[@]}"
fi
