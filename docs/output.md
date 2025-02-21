# nf-core/multiplesequencealign: Output

## Introduction

This document describes the output produced by the pipeline. See [`main README.md`](../README.md) for a condensed overview of the steps in the pipeline, and the bioinformatics tools used at each step.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

1. **Input files summary**: (Optional) computation of summary statistics on the input fasta file, such as the average sequence similarity across the input sequences, their length, etc. Skip by `--skip_stats` as a parameter.
2. **Guide Tree**: (Optional) Renders a guide tree.
3. **Align**: aligns the sequences.
4. **Evaluate**: (Optional) The obtained alignments are evaluated with different metrics: Sum Of Pairs (SoP), Total Column score (TC), iRMSD, Total Consistency Score (TCS), etc. Skip by passing `--skip_eval` as a parameter.
5. **Report**: Reports about the collected information of the runs are reported in a shiny app and a summary table in multiqc. Skip by passing `--skip_shiny` and `--skip_multiqc`.

## Input files summary

The stats.nf subworkflow collects statistics about the input files and summarizes them into a final csv file.

<details markdown="1">
<summary>Output files</summary>

- `summary/stats/`
  - `complete_summary_stats.csv`: csv file containing the summary for all the statistics computed on the input file.
  - `sequences/`
    - `seqstats/*_seqstats.csv`: file containing the sequence input length for each sequence in the family defined by the file name. If `--calc_seq_stats` is specified.
    - `perc_sim/*_txt`: file containing the pairwise sequence similarity for all input sequences. If `--calc_sim` is specified.
  - `structures/` - `plddt/*_full_plddt.csv`: file containing the plddt of the structures for each sequence in the input file. If `--extract_plddt` is specified.
  </details>

## Trees

If you explicitly specifified (via the toolsheet) to compute guidetrees to be used by the MSA tool, those are stored here.

<details markdown="1">
<summary>Output files</summary>

- `trees/`
  - `*/*.dnd`: guide tree files.

</details>

## Alignment

All MSA computed are stored here.

<details markdown="1">
<summary>Output files</summary>

- `alignment/`
  - `*/*.fa`: each subdirectory is named after the sample id. It contains all the alignments computed on it. The filename contains all the informations of the input file used and the tool.
    The file naming convention is:
    {Input*file}*{Tree}_args-{Tree_args}_{MSA}\_args-{MSA_args}.aln

</details>

## Evaluation

Files with the summary of the computed evaluation statistics.

<details markdown="1">
<summary>Output files</summary>

- `evaluation/`
  - `tcoffee_irmsd/`: directory containing the files with the complete iRMSD files. If `--calc_irmsd` is specified.
  - `tcoffee_tcs/`: directory containing the files with the complete TCS files. If `--calc_tcs` is specified.
  - `complete_summary_eval.csv`: csv file containing the summary of all evaluation metrics for each input file.
  </details>

## Shiny App

<details markdown="1">
<summary>Output files</summary>

- `shiny_app/`
  - `run.sh`: executable to start the shiny app.
  - `*.py*`: shiny app files.
  - `*.csv`: csv file used by shiny app.
  - `trace.txt`: trace file used by shiny app.
  </details>

The if `--skip_shiny=false` is specified, a shiny app is prepared to visualize the summary statistics and evaluation of the produced alignments.
To run the shiny app:
`cd shiny_app`
`./run.sh`

Be aware that you have to have [shiny](https://shiny.posit.co/py/) installed to access this feature.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
