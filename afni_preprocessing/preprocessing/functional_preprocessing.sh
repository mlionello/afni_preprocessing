#!/usr/bin/bash

# Set script path and source additional script
script_path=$(dirname "$(readlink -f "$0")")
source "$script_path"/toprint.sh

# Parameters passed from the main script
data_folder="$1"
outputfolder="$2"
num_cpus="$3"
compute_func="$4"
performTShift="$5"
tShiftchar="$6"
vox_res="$7"
fwh="$8"
mnitemp="${9}"
ciric="${10}"
deconv_single_run="${11}"
tasks_regressors="${12}"
onset_regressor="${13}"
TR="${14}"
num_subjs="${15}"
num_runs="${16}"
subjs=("${@:17:$num_subjs}")
runs=("${@:($num_subjs + 17):$num_runs}")

num_steps=12
[[ "$performTShift" -eq 1 ]] && num_steps=$((num_steps + 1))
[[ ! "$deconv_single_run" -eq 1 ]] && num_steps=$((num_steps - 2))

conv_stim_confounds=$([[ "$tasks_regressors" -eq 1 || "$onset_regressor" -eq 1 ]] && echo '1' || echo '0');

for i in "${!subjs[@]}"; do
  subj="${subjs[i]}"
  insubj="$data_folder"/"$subj"
  outsubj="$outputfolder"/"$subj"
  for r in "${!runs[@]}"; do
    mkdir -p "$outsubj"/func
    current_file_stem=$(echo "$0" | awk -F"/" '{print $NF}' | sed 's/\.[^.]*$//')
    cp "$0" "${outsubj}/func/${current_file_stem}_$(date +"%Y%m%d_%H%M%S").sh"
    s=0
    run="${runs[$r]}"

    boldid=$(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]${run}*bold.nii.gz" -type f -exec basename {} \; | cut -d. -f1)
    events_file=$(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]${run}*events.tsv" -type f -exec basename {} \;)
    events_file="$insubj"/func/"$events_file"

    inputBet="$insubj"/func/"$boldid"
    [[ "$performTShift" -eq 1 ]] && inputBet="$outsubj"/func/"$boldid"-t
    subjStem="$outsubj"/func/"$boldid"
    outBet="$subjStem"-"$tShiftchar"_bet
    outVol="$subjStem"-"$tShiftchar"v
    outMNI="$subjStem"-"$tShiftchar"v_2mni
    outMNIBlur="$subjStem"-"$tShiftchar"v_2mni_blur
    outMNIBlurNorm="$subjStem"-"$tShiftchar"v_2mni_norm
    outMNIpreproc="$subjStem"_preprocessed
    outMNIdespiked="$subjStem"_prepr_despiked
    confound_concat="$outsubj"/func/"$subj"_confounds_runscat.1D
    confounds_stim_concat="$outsubj"/func/"$subj"_confounds_runscat_stim.1D
    onset_stim_char=""; [[ $"onset_regressor" -eq 1 ]] && onset_stim_char="OnsetStim_"
    task_stim_char=""; [[ $"tasks_regressors" -eq 1 ]] && tasks_regressors="TaskStim"
    matrix_intersec="$outsubj"/func/"$subj"v_2mni_mask_inters.nii.gz
    out_deconvolve_cat="${outsubj}/func/${subj}_run-all_v_2mni_norm_preproc${onset_stim_char}${tasks_regressors}.nii.gz"
    out_deconvolve_cat_despiked="${outsubj}/func/${subj}_run-all_v_2mni_norm_preproc${onset_stim_char}${tasks_regressors}_despiked.nii.gz"
    logfile="$outsubj"/func/log.txt

    if [[ ! -h "$subjStem".nii.gz ]]; then
      target_file="$inputBet".nii.gz
      while [[ -h $target_file ]]; do
        target_file=$(readlink "$target_file")
      done
      ln -s "$target_file" "$subjStem".nii.gz
    fi

    ## TIME-SHIFT (OPTIONAL for TR<2s)
    if [[ "$performTShift" -eq 1 ]]; then
      toprint 3dTshift $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
      awk '/SliceTiming/,/]/' "$insubj"/func/"$boldid".json | \
        tr -d '\t|SliceTiming|:|"|[|]|,' | \
        tr '\n' ' ' > "$outsubj"/func/slice_timing.txt
      3dTshift -tzero 0 \
        -prefix "$inputBet".nii.gz \
        -tpattern @"$outsubj"/func/slice_timing.txt \
        "$insubj"/func/"$boldid".nii.gz >> "$logfile" 2>&1
    fi

    ## BET
    toprint bet $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outBet".nii.gz ]]; then
      bet "$inputBet".nii.gz "$outBet".nii.gz -F >> "$logfile" 2>&1
    fi

    ## VOLREG
    toprint 3dvolreg $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outVol".nii.gz ]] || [[ ! -e "$outVol"_params.1D ]]; then
      [[ -e "$outVol".nii.gz ]] && rm "$outVol".nii.gz
      [[ -e "$outVol"_params.1D ]] && rm "$outVol"_params.1D
      [[ -e "$outVol"_matrix.aff12.1D ]] && rm "$outVol"_matrix.aff12.1D
      my_base="0";
      if [[ ! "$deconv_single_run" -eq 1 && "$run" -eq "02" ]]; then
        bettun1=$(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]01*"bold.nii.gz -type f -exec basename {} \; | cut -d. -f1)
        subjStemrun1="$outsubj"/func/"$boldid"
        outBetrun1="$subjStemrun1"-"$tShiftchar"_bet.nii.gz
        my_base="$outBetrun1"[0]
      fi
      3dvolreg -base "$my_base" \
        -prefix "$outVol".nii.gz \
        -1Dfile "$outVol"_params.1D \
        -1Dmatrix_save "$outVol"_matrix.aff12.1D \
        -maxdisp1D "$outVol"_maxdisp.1D \
        "$outBet".nii.gz >> "$logfile" 2>&1
    fi

    ## COMPUTE CONFOUND VECTORS
    [[ -e "$outVol"_confounds.1D ]] && rm "$outVol"_confounds.1D
    confounds=("$outVol"_params.1D) # (6P)
    if [[ "$ciric" -eq 1 ]]; then ##COMPUTE CIRIC CORRECTIONS
      # extract CSF and WM average signal ( + 2P = 8P)
      [[ ! -e "$outVol"_tissue1_mean.1D || ! -e "$outVol"_tissue3_mean.1D || ! -e "$outVol"_gs_mean.1D ]] && \
        [[ -e "$outVol"_confounds9P.1D ]] && rm "$outVol"_confounds9P.1D
      if [[ ! -e "$outVol"_confounds9P.1D ]]; then
        for tissueType in 1 3; do
          confounds+=("$outVol"_tissue"$tissueType"_mean.1D)
          [[ -e "$outVol"_tissue"$tissueType"_mean.1D ]] && rm "$outVol"_tissue"$tissueType"_mean.1D
          if [[ ! -e "$outVol"_restoreTissue"$tissueType"_resampled.nii.gz ]]; then
            3dresample -master "$outVol".nii.gz \
              -prefix "$outVol"_restoreTissue"$tissueType"_resampled.nii.gz \
              -input "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreTissue"$tissueType".nii.gz >> "$logfile" 2>&1
          fi
          3dROIstats -mask "$outVol"_restoreTissue"$tissueType"_resampled.nii.gz \
            "$outVol".nii.gz > "$outVol"_tissue"$tissueType"_mean.tmp 2>> "$logfile"
          awk 'NR > 1 {print $3}' "$outVol"_tissue"$tissueType"_mean.tmp > "$outVol"_tissue"$tissueType"_mean.1D
        done

        # extract GSR ( + 1P = 9P)
        [[ -e "$outVol"_gs_mean.1D ]] && rm "$outVol"_gs_mean.1D
        if [[ ! -e "$outVol"_restoreBrainExtractionMask_resampled.nii.gz ]]; then
          3dresample -master "$outVol".nii.gz \
            -prefix "$outVol"_restoreBrainExtractionMask_resampled.nii.gz \
            -input "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionMask.nii.gz >> "$logfile" 2>&1
        fi
        3dROIstats -mask "$outVol"_restoreBrainExtractionMask_resampled.nii.gz \
          "$outVol".nii.gz > "$outVol"_gs_mean.tmp 2>> "$logfile"
        awk 'NR > 1 {print $3}' "$outVol"_gs_mean.tmp > "$outVol"_gs_mean.1D

        confounds+=("$outVol"_gs_mean.1D)

        # new regressor file for 9 columns
        paste "${confounds[@]}" > "$outVol"_confounds9P.1D

      else # if confounds9P already exists, just update the confounds file list
        for tissueType in 1 3; do confounds+=("$outVol"_tissue"$tissueType"_mean.1D); done
        confounds+=("$outVol"_gs_mean.1D)
      fi

      # compute derivatives ( + 9P = 18P)
      if [[ ! -e "$outVol"_confounds_derivate.1D ]]; then
        num_columns=$(awk '{print NF}' "$outVol"_confounds9P.1D | head -n 1)
        cp "$outVol"_confounds9P.1D "$outVol"_confounds_copy.tmp
        cp "$outVol"_confounds9P.1D "$outVol"_confounds_copy2.tmp
        sed -i '1d' "$outVol"_confounds_copy.tmp # remove first timepoints
        sed -i '$d' "$outVol"_confounds_copy2.tmp # remove last timepoints

        for ((column=1; column<"$num_columns"+1; column++)); do # for each regressor from the columns of the file
          paste <(awk -v col="$column" '{printf "%.6f\n", $col}' "$outVol"_confounds_copy.tmp) \
            <(awk -v col="$column" '{printf "%.6f\n", $col}' "$outVol"_confounds_copy2.tmp) \
            | awk -v tr="$TR" '{printf "%.6f\n", ($1 - $2) / tr}' > "$outVol"_confounds_derivate_col.tmp
          # repeat first and last element of the derivatives
          last_element=$(tail -n 1 "$outVol"_confounds_derivate_col.tmp)
          echo "$last_element" >> "$outVol"_confounds_derivate_col.tmp
          # save regressor derivatives to a separate file
          if [[ ! -e "$outVol"_confounds_derivate.1D ]]; then
            mv "$outVol"_confounds_derivate_col.tmp "$outVol"_confounds_derivate.1D
          else
            paste "$outVol"_confounds_derivate.1D "$outVol"_confounds_derivate_col.tmp > "$outVol"_confounds_derivate_col_ccat.tmp
            mv "$outVol"_confounds_derivate_col_ccat.tmp "$outVol"_confounds_derivate.1D ### here i get 22 by 21 matrix
          fi
        done
        rm "$outVol"_confounds_copy.tmp "$outVol"_confounds_copy2.tmp
      fi
      confounds+=("$outVol"_confounds_derivate.1D)

      # compute squares of the time series ( + 9P = 27P) to a separate file
      [[ ! -e "$outVol"_confounds_squared.1D ]] && \
        awk '{for (col=1; col<=NF; col++) $col = $col * $col} 1' "$outVol"_confounds9P.1D > "$outVol"_confounds_squared.1D
      confounds+=("$outVol"_confounds_squared.1D)

      # compute squares of the derivatives ( + 9P = 36P) to a separate file
      [[ ! -e "$outVol"_confounds_derivate_squared.1D ]] && \
        awk '{for (col=1; col<=NF; col++) $col = $col * $col} 1' "$outVol"_confounds_derivate.1D > "$outVol"_confounds_derivate_squared.1D
      confounds+=("$outVol"_confounds_derivate_squared.1D)
    fi

    nb_lines=-1
    for confound_file in "${confounds[@]}"; do
      tmp=$(wc -l < "$confound_file")
      if [[ "$tmp" -eq "$nb_lines" ]] || [[ "$nb_lines" -eq -1 ]]; then
        nb_lines=$tmp
      else
        printf "\n\nERROR while pasting %s moco confounds: one column has (%d) timepoints while the previous one has (%d) timepoints!\n\n\n", "$confound_file", "$tmp", "$nb_lines"
        exit
      fi
    done
    paste -d ' ' "${confounds[@]}" > "$outVol"_confounds.1D
    confound_files+=("$outVol"_confounds.1D)

    # a list of the "$outVol"_confounds_stim.1D files is used later
    # "$outVol"_confounds_stim.1D must be computed online; if a previous version is present, remove it
    [[ -e "$outVol"_confounds_stim.1D ]] && rm "$outVol"_confounds_stim.1D
    if [[ "$conv_stim_confounds" -eq 1 ]]; then
      unset confounds_stim
      if [[ "$onset_regressor" -eq 1 ]]; then
        confounds_stim+=("$outVol"_confounds_onsets.1D)
        if [[ ! -e "$outVol"_confounds_onsets.1D ]]; then # this works only with TR=1
          # last starts from 2 as the first timepoints will be set to 1
          awk 'NR>1{print $1}' "$events_file" > "$outVol"_confounds_onsets_times.1D
          awk 'NR>1{print $1+$2}' "$events_file" | awk 'BEGIN{last=2} {for (i=last; i<$1; i++) print "0"; print "1"; last=$1+1}' > "$outVol"_confounds_onsets.tmp
          printf "1\n" | cat - "$outVol"_confounds_onsets.tmp > "$outVol"_confounds_onsets.1D && rm "$outVol"_confounds_onsets.tmp
        fi
      fi

      if [[ "$tasks_regressors" -eq 1 ]]; then
        confounds_stim+=("$outVol"_confounds_task.1D)
        if [[ ! -e "$outVol"_confounds_task.1D ]]; then # this works only with TR=1
          sed -i '/^$/d' "$events_file"
          echo "nr_task stim_name" > "$outVol"_TaskNrByAlphab.tsv
          awk 'NR>1 {print $3, NR}' "$events_file" | sort | awk '{printf "%03d %s \n", $2-2, $1}' >> "$outVol"_TaskNrByAlphab.tsv
          read -ra order <<< $(awk 'NR>1 {print $1, NR}' "$outVol"_TaskNrByAlphab.tsv | sort | awk '{print $2-2}' ORS=' ')
          echo "${order[@]}" > "$outVol"_tasks_order.1D
          num_columns=$(($(wc -l < "$events_file") - 1))
          # for some reason sort_cols elements starts form index 1?!?!?!
          awk -v tr="$TR" 'NR>1 {print $1+$2}' "$events_file" \
           | awk -v nb_columns="$num_columns" -v order="${order[*]}" 'BEGIN{last=0; col_i=0; split(order, sort_cols)} {col=sort_cols[++col_i]; for (k=last; k<$1; k++) { for (j=0; j<col; j++) printf "0 "; printf "1 "; for (j=col+1; j<=nb_columns; j++) printf "0 "; printf "\n";}  last=$1;}' > "$outVol"_confounds_task.1D
        fi
      fi

      nb_lines=-1
      for confound_file in "${confounds_stim[@]}"; do
        tmp=$(wc -l < "$confound_file")
        if [[ "$tmp" -eq "$nb_lines" ]] || [[ "$nb_lines" -eq -1 ]]; then
          nb_lines=$tmp
        else
          printf "\n\nERROR while pasting %s stimuli confounds: one stimuli has (%d) timepoints while the previous one has (%d) timepoints!\n\n\n", "$confound_file", "$tmp", "$nb_lines"
          exit
        fi
      done
      paste -d ' ' "${confounds_stim[@]}" > "$outVol"_confounds_stim.1D
      confound_stim_files+=("$outVol"_confounds_stim.1D)
    fi

    toprint 3dTstat $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outVol"_avg.nii.gz ]]; then
      3dTstat -prefix "$outVol"_avg.nii.gz \
        "$outVol".nii.gz >> "$logfile" 2>&1
    fi

    ## ALIGNING AVG VolReg with ANTS output
    toprint align_epi_anat.py $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outVol"_avg_al_mat.aff12.1D ]]; then
      align_epi_anat.py -epi_base 0 -epi2anat -giant_move \
        -epi "$outVol"_avg.nii.gz \
        -anat "$outsubj"/anat/"$subj"_T1w_2acpc_brain_restoreBrainExtractionBrain.nii.gz \
        -anat_has_skull no -epi_strip None -volreg off -tshift off \
        -deoblique off \
        -overwrite \
        -master_epi 1 -cost lpc+ZZ -output_dir "$outsubj"/func/ >> "$logfile" 2>&1
    fi

    toprint 3dNwarpApply-AVG $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNI"_avg.nii.gz ]]; then
      3dNwarpApply -interp wsinc5 -dxyz "$vox_res" \
        -nwarp "$outsubj"/anat/"$subj"_T1w_2acpc_restore_2mni_WARP.nii.gz \
        "$outVol"_avg_al_mat.aff12.1D \
        -master "$mnitemp" \
        -source "$outVol"_avg.nii.gz \
        -prefix "$outMNI"_avg.nii.gz >> "$logfile" 2>&1
    fi

    toprint 3dNwarpApply-Mask $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNI"_mask.nii.gz ]]; then
      3dNwarpApply -interp NN -dxyz "$vox_res" \
        -nwarp "$outsubj"/anat/"$subj"_T1w_2acpc_restore_2mni_WARP.nii.gz \
        "$outVol"_avg_al_mat.aff12.1D \
        -master "$mnitemp" \
        -source "$outBet"_mask.nii.gz \
        -prefix "$outMNI"_mask.nii.gz >> "$logfile" 2>&1
    fi

    toprint 3dNwarpApply-EPI $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNI".nii.gz ]]; then
      3dNwarpApply -interp wsinc5 -dxyz "$vox_res" \
        -nwarp "$outsubj"/anat/"$subj"_T1w_2acpc_restore_2mni_WARP.nii.gz \
        "$outVol"_avg_al_mat.aff12.1D \
        "$outVol"_matrix.aff12.1D \
        -master "$mnitemp" \
        -source "$outBet".nii.gz \
        -prefix "$outMNI".nii.gz >> "$logfile" 2>&1
    fi

    ## BLURRING
    toprint 3dBlurToFWHM $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNIBlur".nii.gz ]]; then
      3dBlurToFWHM -FWHM "$fwh" -detrend \
        -input "$outMNI".nii.gz \
        -prefix "$outMNIBlur".nii.gz \
        -mask "$outMNI"_mask.nii.gz >> "$logfile" 2>&1
    fi

    ## NORMALIZATION
    toprint 3dTstat $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNIBlur"_avg.nii.gz ]]; then
      3dTstat -prefix "$outMNIBlur"_avg.nii.gz \
        "$outMNIBlur".nii.gz >> "$logfile" 2>&1
    fi

    toprint 3dcalc $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    if [[ ! -e "$outMNIBlurNorm".nii.gz ]]; then
      3dcalc -a "$outMNIBlur".nii.gz \
        -b "$outMNIBlur"_avg.nii.gz \
        -expr 'a/b*100' \
        -prefix "$outMNIBlurNorm".nii.gz >> "$logfile" 2>&1
    fi

    if [[ "$deconv_single_run" -eq 1 ]]; then
      ## DECONVOLUTION
      toprint 3dDeconvolve $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
      if [[ ! -e "$outMNIpreproc".nii.gz ]]; then
        3dDeconvolve -jobs "$num_cpus" -nobucket -polort A \
          -input "$outMNIBlurNorm".nii.gz \
          -ortvec "$outVol"_confounds.1D confounds \
          -mask "$outMNI"_mask.nii.gz \
          -x1D "$outMNI"_preproc.xmat.1D \
          -errts "$outMNIpreproc".nii.gz >> "$logfile" 2>&1
      fi

      # Despike
      toprint 3dDespike $((++s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
      if [[ ! -e "$outMNIdespiked".nii.gz ]]; then
        3dDespike -nomask -prefix "$outMNIdespiked".nii.gz \
          "$outMNIpreproc".nii.gz >> "$logfile" 2>&1
      fi
    fi
  done

  if [[ ! "$deconv_single_run" -eq 1 ]] && [[ "$run" -eq "${runs[-1]}" ]]; then
    mapfile -t events_file_tmp < <(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]01*events.tsv" -type f)
    mapfile -t -O "${#events_file_tmp[@]}" events_file_tmp < <(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]02*events.tsv" -type f)
    # Initialize arrays
    last_offset=0
    # Process each file in the events_file_tmp array
    echo "onset duration filename" > "$outsubj"/func/"$subj"_confounds_runscat_stim_onset_times.1D
    for file in "${events_file_tmp[@]}"; do
        # Use awk to extract the value from the first and second columns of the last row
        awk -v offset="$last_offset" 'NR>1 {print $1 + offset, $2, $3}' "$file" >> "$outsubj"/func/"$subj"_confounds_runscat_stim_onset_times.1D
        last_row_values=($(awk 'END {print $1, $2}' "$file"))
        # Add the values to the sums
        last_offset=$((last_row_values[0] + last_row_values[1] + last_offset))
    done

    # list of confound_files - moco and ciric
    column_counts=($(awk 'FNR==1{print NF}' "${confound_files[@]}" | sort -u))
    # list of confound_stim_files - stimuli
    if [[ "$conv_stim_confounds" -eq 1 ]]; then
      stim_column_counts=($(awk 'FNR==1{print NF}' "${confound_stim_files[@]}" | sort -u))
      # get number of timesteps from stimuli time annotations for each run
      mapfile -t num_tsteps < <(wc -l "${confound_stim_files[@]}" | awk '{print $1}')
      tot_time_stim_steps=$((num_tsteps[0] + num_tsteps[1]))
    else
      num_tsteps=()
      for run in "${runs[@]}"; do
      events_file=$(find "$insubj"/func -name "*${subj//-/[_-]}*_run[_-]${run}*events.tsv" -type f -exec basename {} \;)
      events_file="$insubj"/func/"$events_file"
      num_tsteps+=($(awk 'END {print $1+$2}' "$events_file"));
      done
      tot_time_stim_steps=$((num_tsteps[0] + num_tsteps[1]))
      printf "\nnumber steps for each run:\n" >> "$logfile"
      printf "%s\t" "${num_tsteps[@]}" >> "$logfile"
      printf "\ntot samples: %s\n\n" "$tot_time_stim_steps" >> "$logfile"
    fi

    [[ ! ${#confound_files[@]} -ge 2 ]] && echo "Error: Insufficient moco files found for concatenation." && exit
    # concatenate the first corresponding num_tsteps of the confounds params
    [[ -e "$confound_concat" ]] && rm "$confound_concat"
    [[ ${#column_counts[@]} -eq 1 ]] && \
      { for ((confound_f=0; confound_f<${#confound_files[@]}; confound_f++)); do head -n "${num_tsteps[confound_f]}" "${confound_files[confound_f]}"; done } >> "$confound_concat"
    [[ ! ${#column_counts[@]} -eq 1 ]] && echo "Error: confound_files have different number of columns." && exit
    # concatenate the stimuli vectors
    if [[ "$conv_stim_confounds" -eq 1 ]]; then
      [[ ! ${#confound_stim_files[@]} -ge 2 ]] && echo "Error: Insufficient stim files found for concatenation." && exit
      [[ -e "$confounds_stim_concat" ]] && rm "$confounds_stim_concat"
      [[ ${#stim_column_counts[@]} -eq 1 ]] && cat "${confound_stim_files[@]}" > "$confounds_stim_concat"
      [[ ! ${#stim_column_counts[@]} -eq 1 ]] && echo "Error: confound_stim_files have different number of columns." && echo "${stim_column_counts[@]}" && exit
    fi

    stim_times_option=""
    if [[ "$conv_stim_confounds" -eq 1 ]]; then
      # make concat stimulus time series into stim_times format
      make_stim_times.py -prefix "$subj"_run-all_stims_times \
        -nruns 1 -nt $tot_time_stim_steps -tr 1 \
        -files "$confounds_stim_concat"
      confound_stim_files_tseries=($(find "$outsubj"/func -type f -name "*_run-all_stims_times*" | sort))
      stim_times_option+="-num_stimts ${#confound_stim_files_tseries[@]} "
      # create stim_times argument for 3ddeconvolve
      for file_i in "${!confound_stim_files_tseries[@]}"; do
        stim_times_option+="-stim_times $((file_i+1)) ${confound_stim_files_tseries[$file_i]} BLOCK(1,1) "
      done
    fi

    if [[ ! -e "$matrix_intersec" ]]; then
      mapfile -t mask_list < <(find "$outsubj"/func -type f -name "*run[_-]0[12]*-v_2mni_mask.nii.gz")
      3dmask_tool -input "${mask_list[@]}" -inters -prefix "$matrix_intersec" >> "$logfile" 2>&1
    fi

    ## DECONVOLUTION
    norm1=$(find "$outsubj"/func -name "*run[_-]01*v_2mni_norm.nii.gz" -type f -exec basename {} \;)
    norm2=$(find "$outsubj"/func -name "*run[_-]02*v_2mni_norm.nii.gz" -type f -exec basename {} \;)
    toprint 3dDeconvolve $((s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    [[ -e "$out_deconvolve_cat" ]] && printf "\nDECONVOLV FILE ALREADY EXISTS, no output\n\n" >> "$logfile"
    if [[ ! -e "$out_deconvolve_cat" ]]; then
      3dDeconvolve -jobs "$num_cpus" -nobucket -polort A \
        -input "$outsubj"/func/"$norm1"[0..$((num_tsteps[0] - 1))] "$outsubj"/func/"$norm2"[0..$((num_tsteps[1] - 1))] \
        -ortvec "$confound_concat" confounds \
        -mask "$matrix_intersec" \
        -x1D "$out_deconvolve_cat".xmat.1D \
        -global_times \
        $stim_times_option \
        -GOFORIT \
        -errts "$out_deconvolve_cat" >> "$logfile" 2>&1
    fi

    # Despike
    toprint 3dDespike $((s)) $((i+1)) $((r+1)) "$num_steps" "$num_subjs" "$num_runs"
    [[ -e "$out_deconvolve_cat_despiked" ]] && printf "\nDESPIKED FILE ALREADY EXISTS, no output\n\n" >> "$logfile"
    if [[ ! -e "$out_deconvolve_cat_despiked" ]]; then
      3dDespike -nomask -prefix "$out_deconvolve_cat_despiked" \
        "$out_deconvolve_cat" >> "$logfile" 2>&1
    fi
  fi
done
