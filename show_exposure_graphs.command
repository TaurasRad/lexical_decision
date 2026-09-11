#!/bin/zsh
cd -- "$(dirname -- "$0")" || exit 1
Rscript plot_exposure.R && open results/exposure_plots.png
