# AFNI Preprocessing Pipeline

Developed by:

Matteo Lionello @ [Social and Affective NEuroscience (SANE), IMT Lucca](https://momilab.imtlucca.it/research/sane)

This repository contains code for a preprocessing pipeline designed for AFNI datasets. The pipeline offers extensive customization options to suit various preprocessing needs.

```
$ ~/afni_preprocessing/preprocessing/main.sh --data_folder /data/raw --output_folder /data/derivatives
subject: 2/3, run 1/2
( ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇..................... ) 66%
3dVolreg... 4/12
( ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇....................................... ) 33%
```

## Installation:

Clone or download this repository.
Modify the script paths in the code (script_path and pckg_path) to point to the locations of your AFNI installation and additional scripts (e.g., anatomical_preprocessing.sh).

## Usage:

The pipeline is executed from the command line using the following syntax inside afni_preprocessing/preprocessing:

./main.sh [OPTIONS]

Options:

    --num_cpus: Number of CPUs to use (default: 16)
    --fwh: Full width at half maximum for smoothing (default: 4)
    --vox_res: Voxel resolution (default: 2)
    --data_folder: Path to the data folder
    --output_folder: Path to the output folder
    --mnitemp: Path to the MNI template
    --onlysubj: Space-separated list of subjects to process (optional)
    --skipsubj: Space-separated list of subjects to skip (optional)
    --compute_anat: Flag to compute anatomical preprocessing (default: 1)
    --compute_func: Flag to compute functional preprocessing (default: 1)
    --performTShift: Flag to perform temporal shifting (default: 0)
    --ciric: Flag for ciric-specific options (default: 1)
    --deconv_single_run: Flag for deconvolution in a single run (default: 1)
    --tasks_regressors: Flag to include task regressors (default: 1)
    --onset_regressor: Flag to include onset regressors (default: 1)
    --tr: Temporal resolution (default: 1)
    --help: Display help message

### Additional Notes:

The code automatically saves a copy of the script with a timestamp upon execution for reference.
Refer to the individual preprocessing scripts (anatomical_preprocessing.sh and functional_preprocessing.sh) for further details on their functionalities.

Please note that this is a general description, and specific details about the preprocessing steps might be found in the code itself or in the additional scripts mentioned.
