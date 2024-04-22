#!/usr/bin/bash

# Set script path and source additional script
script_path=$(dirname "$(readlink -f "$0")")
source ../utils/toprint.sh

# Parameters passed from the main script
data_folder="$1"
outputfolder="$2"
num_cpus="$3"
subjs="$4"
mnitemp="$5"
tissue_segmentation="$6"
num_subjs="${7}"
subjs=("${@:8:$num_subjs}")

num_steps=3
[[ "$tissue_segmentation" -eq 1 ]] && num_steps=$((num_steps + 1))

for i in "${!subjs[@]}"; do
  s=0
  subj="${subjs[i]}"
  insubj="$data_folder"/"$subj"
  outsubj="$outputfolder"/"$subj"
  mkdir -p "$outsubj"/anat
  current_file_stem=$(echo "$0" | awk -F"/" '{print $NF}' | sed 's/\.[^.]*$//')
  cp "$0" "${outsubj}/anat/${current_file_stem}_$(date +"%Y%m%d_%H%M%S").sh"

  if [[ ! -h "$outsubj"/anat/"$subj"_T1w.nii.gz ]]; then
    target_file="$insubj"/anat/"$subj"_T1w.nii.gz
    while [[ -h $target_file ]]; do
      target_file=$(readlink "$target_file")
    done
    ln -s "$target_file" "$outsubj"/anat/"$subj"_T1w.nii.gz
  fi

  donotclear=0 && [[ i -eq 0 ]] && donotclear=1
  toprint fslreorient2std $((++s)) $((i+1)) 0 ${num_steps} ${num_subjs} ${num_runs} ${donotclean}
  if [[ ! -e "$outsubj"/anat/"$subj"_T1w_reor.nii.gz ]]; then
    fslreorient2std "$insubj"/anat/"$subj"_T1w.nii.gz \
      "$outsubj"/anat/"$subj"_T1w_reor.nii.gz >> "$outsubj"/anat/log.txt  2>&1
  fi

  toprint antsBrainExtraction $((++s)) $((i+1)) '-' ${num_steps} ${num_subjs} '-'
  if [[ ! -e "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionBrain.nii.gz ]]; then
    /home/programmi/ANTS-v2.3.5-126/bin/antsBrainExtraction.sh -d 3 -a "$outsubj"/anat/"$subj"_T1w_reor.nii.gz \
    -e templates/oasis/T_template0.nii.gz \
    -m templates/oasis/T_template0_BrainCerebellumProbabilityMask.nii.gz \
    -f templates/oasis/T_template0_BrainCerebellumExtractionMask.nii.gz \
    -o "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restore >> "$outsubj"/anat/log.txt 2>&1
  fi

  toprint 3dQwarp $((++s)) $((i+1)) '-' ${num_steps} ${num_subjs} '-'
  if [[ ! -e "$outsubj"/anat/"$subj"_T1w_2acpc_restore_2mni.nii.gz ]]; then
    3dQwarp -allineate -blur 0 3 \
    -allopt '-cost nmi -automask -twopass -final wsinc5' \
    -minpatch 17 \
    -useweight \
    -base "$mnitemp" \
    -source "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionBrain.nii.gz \
    -prefix "$outsubj"/anat/"$subj"_T1w_2acpc_restore_2mni.nii.gz \
    -iwarp >> "$outsubj"/anat/log.txt 2>&1
  fi

  if [[ "$tissue_segmentation" -eq 1 ]]; then
    toprint 3dSeg $((++s)) $((i+1)) '-' ${num_steps} ${num_subjs} '-' #pipeline ciric benchmarking resting state motion correction 2016/17
    if [[ ! -e "$outsubj"/anat/segm ]]; then
      3dSeg -anat "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionBrain.nii.gz \
        -mask "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionMask.nii.gz \
        -classes 'CSF ; GM ; WM' \
        -prefix "$outsubj"/anat/segm >> "$outsubj"/anat/log.txt 2>&1
    fi

    for tissueType in 1 2 3; do
      if [[ ! -e "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreTissue"$tissueType".nii.gz ]]; then
        3dcalc -a "$outsubj"/anat/segm/Classes+orig.HEAD \
          -expr "ifelse(equals(a,"$tissueType"), a, 0)" \
          -prefix "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreTissue"$tissueType".nii.gz  >> "$outsubj"/anat/log.txt 2>&1
      fi
    done
  fi
done
