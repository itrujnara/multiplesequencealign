/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { paramsSummaryMap       } from 'plugin/nf-validation'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_multiplesequencealign_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Local subworkflows
//
include { STATS                  } from '../subworkflows/local/stats'
include { ALIGN                  } from '../subworkflows/local/align'
include { EVALUATE               } from '../subworkflows/local/evaluate'
include { CREATE_TCOFFEETEMPLATE } from '../modules/local/create_tcoffee_template'

//
// MODULE: local modules
//
include { PREPARE_MULTIQC } from '../modules/local/prepare_multiqc'
include { PREPARE_SHINY   } from '../modules/local/prepare_shiny'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { UNTAR                          } from '../modules/nf-core/untar/main'
include { CSVTK_JOIN as MERGE_STATS_EVAL } from '../modules/nf-core/csvtk/join/main.nf'
include { PIGZ_COMPRESS                  } from '../modules/nf-core/pigz/compress/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow MULTIPLESEQUENCEALIGN {

    take:
    ch_input    // channel: [ meta, path(sequence.fasta), path(reference.fasta), path(pdb_structures.tar.gz), path(templates.txt) ]
    ch_tools    // channel: [ val(guide_tree_tool), val(args_guide_tree_tool), val(alignment_tool), val(args_alignment_tool) ]
    ch_versions // channel: [ path(versions.yml) ]

    main:
    ch_multiqc_files             = Channel.empty()
    ch_multiqc_table             = Channel.empty()
    evaluation_summary           = Channel.empty()
    stats_summary                = Channel.empty()
    stats_and_evaluation_summary = Channel.empty()
    ch_shiny_stats               = Channel.empty()

    ch_input
        .map {
            meta, fasta, ref, str, template ->
                [ meta, file(fasta) ]
        }
        .set { ch_seqs }

    ch_input
        .filter { it[2].size() > 0}
        .map {
            meta, fasta, ref, str, template ->
                [ meta, file(ref) ]
        }
        .set { ch_refs }

    ch_input
        .filter { it[4].size() > 0}
        .map {
            meta, fasta, ref, str, template ->
                [ meta, file(template) ]
        }
        .set { ch_templates }

    ch_input
        .map {
            meta, fasta, ref, str, template ->
                [ meta, str ]
        }
        .filter { it[1].size() > 0 }
        .set { ch_structures }

    // ----------------
    // STRUCTURES
    // ----------------
    // Structures are taken from a directory of PDB files.
    // If the directory is compressed, it is uncompressed first.
    ch_structures
        .branch {
            compressed:   it[1].endsWith('.tar.gz')
            uncompressed: true
        }
        .set { ch_structures }

    UNTAR (ch_structures.compressed)
        .untar
        .mix(ch_structures.uncompressed)
        .map {
            meta,dir ->
                [ meta,file(dir).listFiles().collect() ]
        }
        .set { ch_structures }

    // ----------------
    // TEMPLATES
    // ----------------
    // If a family does not present a template but structures are provided, create one.
    ch_structures_template = ch_structures.join(ch_templates, by:0, remainder:true)
    ch_structures_template
        .branch {
            template: it[2] != null
            no_template: true
        }
        .set { ch_structures_branched }

    // Create the new templates and merge them with the existing templates
    CREATE_TCOFFEETEMPLATE (
        ch_structures_branched.no_template
            .map {
                meta,structures,template ->
                    [ meta, structures ]
            }
    )
    new_templates = CREATE_TCOFFEETEMPLATE.out.template
    ch_structures_branched.template
        .map {
            meta,structures,template ->
                [ meta, template ]
        }
        .set { forced_templates }

    ch_templates_merged = forced_templates.mix(new_templates)

    // Merge the structures and templates channels, ready for the alignment
    ch_structures_template = ch_templates_merged.combine(ch_structures, by:0)

    //
    // Compute summary statistics about the input sequences
    //
    if (!params.skip_stats) {
        STATS (
            ch_seqs,
            ch_structures
        )
        ch_versions   = ch_versions.mix(STATS.out.versions)
        stats_summary = stats_summary.mix(STATS.out.stats_summary)
    }

    //
    // Align
    //
    compress_during_align = !params.skip_compression && params.skip_eval
    ALIGN (
        ch_seqs,
        ch_tools,
        ch_structures_template,
        compress_during_align
    )
    ch_versions = ch_versions.mix(ALIGN.out.versions)

    if (!params.skip_compression && !compress_during_align) {
        PIGZ_COMPRESS (ALIGN.out.msa)
        ch_versions = ch_versions.mix(PIGZ_COMPRESS.out.versions)
    }

    //
    // Evaluate the quality of the alignment
    //
    if (!params.skip_eval) {
        EVALUATE (ALIGN.out.msa, ch_refs, ch_structures_template)
        ch_versions        = ch_versions.mix(EVALUATE.out.versions)
        evaluation_summary = evaluation_summary.mix(EVALUATE.out.eval_summary)
    }

    //
    // Combine stats and evaluation reports into a single CSV
    //
    if (!params.skip_stats || !params.skip_eval) {
        stats_summary_csv = stats_summary.map{ meta, csv -> csv }
        eval_summary_csv  = evaluation_summary.map{ meta, csv -> csv }
        stats_summary_csv.mix(eval_summary_csv)
                        .collect()
                        .map {
                            csvs ->
                                [ [ id:"summary_stats_eval" ], csvs ]
                        }
                        .set { stats_and_evaluation }
        MERGE_STATS_EVAL (stats_and_evaluation)
        stats_and_evaluation_summary = MERGE_STATS_EVAL.out.csv
        ch_versions                  = ch_versions.mix(MERGE_STATS_EVAL.out.versions)
    }

    //
    // MODULE: Shiny
    //
    if (!params.skip_shiny) {
        shiny_app = Channel.fromPath(params.shiny_app)
        PREPARE_SHINY (stats_and_evaluation_summary, shiny_app)
        ch_shiny_stats = PREPARE_SHINY.out.data.toList()
        ch_versions = ch_versions.mix(PREPARE_SHINY.out.versions)
    }

    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    multiqc_out = Channel.empty()
    if (!params.skip_multiqc && (!params.skip_stats || !params.skip_eval)) {

        ch_multiqc_config                     = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
        ch_multiqc_custom_config              = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
        ch_multiqc_logo                       = params.multiqc_logo ? Channel.fromPath(params.multiqc_logo, checkIfExists: true) : Channel.empty()
        summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
        ch_workflow_summary                   = Channel.value(paramsSummaryMultiqc(summary_params))
        ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
        ch_methods_description                = Channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_collated_versions)
        ch_multiqc_files                      = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: false))

        PREPARE_MULTIQC (stats_and_evaluation_summary)
        ch_multiqc_files                      = ch_multiqc_files.mix(PREPARE_MULTIQC.out.multiqc_table.collect{it[1]}.ifEmpty([]))

        MULTIQC (
            ch_multiqc_files.collect(),
            ch_multiqc_config.toList(),
            ch_multiqc_custom_config.toList(),
            ch_multiqc_logo.toList(),
            [],
            []
        )
        multiqc_out = MULTIQC.out.report.toList()
    }

    emit:
    versions = ch_versions // channel: [ path(versions.yml) ]
    multiqc  = multiqc_out // channel: [ path(multiqc_report.html) ]
}



/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


