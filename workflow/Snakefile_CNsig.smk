# Title: Snakefile_CNsig.smk
# Author: Guyuan TANG
# Date: 2023/12/27 - 2024/1/2

import pandas as pd

from scripts.common import get_output_absolute

# specify the configuration file
configfile: "config/config.yaml"

# specify the working directory
working_dir = config['workdir']
if working_dir[-1] != '/':
    working_dir = working_dir + '/'

# specify the results location (output directory)
results = config['outputdir']
if results[-1] != '/':
    results = results + '/'

# specify the sample information
sample_df = (pd.read_csv(config['samp_solutions'], 
    sep='\t',
    dtype={'Sample':str, 'Binsize':str, 'rds':str, 'Ploidy':float, 'Cellularity':float})
    .set_index('Sample', drop=False))

# specify the final output of the workflow
"""
The final output of this workflow should be the signature similarity matrix for each type of signature.
"""
rule all:
    input:
        CN_sig_SS = results + 'signatures/CN_sig/CN_sig.SSmatrix.rds',
        PanCan_sig_SS = results + 'signatures/PanCan_sig/PanCan_sig.SSmatrix.rds'


########## 1 Absolute copy number profiles ####################
"""
The final output for this step should be a segmented copy number profile (tsv) for each sample.
"""
rule absolute_seg_CN:
    input:
        files = get_output_absolute(sample_df, results)

# 1.1 prepare the rascal environment
rule rascal_env:
    output:
        "log/rascal_settle_info2.txt"
    conda: 'envs/rascal.yaml'
    script: 'scripts/rascal_env.R'

# 1.2 calculate the segmented absolute copy number profiles for each sample
rule rascal_absolute_CN:
    ### rascal will be used to calculate the absolute copy numbers and to apply segmentation
    input:
        env_set = 'log/rascal_settle_info2.txt',
        sample_table = config['samp_solutions'],
        rds = lambda wildcards: sample_df.loc[wildcards.sample, 'rds']
    output:
        results + '{sample}/05_absolute_CN/{sample}_{binsize}kb_seg.tsv'
    wildcard_constraints:
        binsize="\d+"
    params:
        sample = '{sample}',
        outdir = results + '{sample}/05_absolute_CN/'
    threads: 5
    conda: 'envs/rascal.yaml'
    script: 'scripts/fit_absoluteCN.R'


########## 2 CN Signatures ####################
"""
The final output for this step would be the matrix files (including a matrix txt file, a matrix object RDS, a simple heatmap for both sample-by-component matrix and sample-by-signature matrix) for all samples. The matrices containing sample-by-signature information.
"""
# 2.1 clone the github repository used for signature validation
rule cn_sig_git:
    output:
        'workflow/scripts/cnsignatures/main_functions.R',
        'workflow/scripts/cnsignatures/helper_functions.R'
    shell: '''
    git clone https://bitbucket.org/britroc/cnsignatures.git 
    mv cnsignatures/ workflow/scripts/
    '''

# 2.2 check all the files are well prepared
rule cn_sig_check:
    input:
        link_up = rules.absolute_seg_CN.input,
        scripts = rules.cn_sig_git.output
    output:
        'log/cn_sig_settle.txt'
    shell: """
    echo 'Finished preparation for signature validation.' > {output}
    """

# 2.3 validate the signatures in our samples
rule CN_signature:
    input:
        # check whether the essential git repository have been downloaded
        main = 'workflow/scripts/cnsignatures/main_functions.R',
        helper = 'workflow/scripts/cnsignatures/helper_functions.R',
        # check all the absolute copy number profiles have successfully been generated
        check_data = rules.cn_sig_check.output,
        # the input segment files
        seg_files = rules.absolute_seg_CN.input
    output:
        CN_sig = results + 'signatures/CN_sig/CN_sig.SSmatrix.rds'
    params:
        sample_info = config['samp_solutions'],
        def_SC = 'workflow/scripts/cnsignatures/data/feat_sig_mat.rds',
        indir = results,
        outdir = results + 'signatures/CN_sig/'
    threads: 20
    conda: 'envs/CNsig.yaml'
    script: 'scripts/CN_sig.R'


########## 3 Pan-Cancer Signatures ####################
"""
The final output for this step should be the validated Pan-cancer signature matrix (sample-by-component) for all samples. The actural outputs include a sample-by-component matrix txt, a full object RDS containing all information (such as activities and weights), two heatmaps (one for activities and one for sample-by-component).
"""
# 3.1 download the PanCan signature definiation table
rule PanCan_def_tab:
    # user should download the supplements manually
    # website: https://www-nature-com.ludwig.lub.lu.se/articles/s41586-022-04789-9#Sec17
    input:
        config['supple_tab']
    output:
        'resources/PanCan.xlsx'
    params:
        select_tab = 'workflow/scripts/select_tab.R',
        folder = config['supple_folder']
    conda: 'envs/PanCanSig.yaml'
    shell:'''
        mv '{input}' resources/Supplementary_Tables_15-22.xlsx
        Rscript {select_tab} -i resources/Supplementary_Tables_15-22.xlsx -o resources/PanCan.xlsx
        rm -r {folder}
    '''

# 3.2 set up the snakemake environment for running the validation
rule PanCan_sig_env:
    input:
        'resources/PanCan.xlsx'
    output:
        "log/PanCan_settle_info.txt"
    conda: 'envs/PanCanSig.yaml'
    script: 'scripts/PanCan_sig_env.R'

# 3.3 use the CINSignatureQuantification package to validate the signatures
rule PanCan_sig:
    input:
        env_set = "log/PanCan_settle_info.txt",
        seg_files = rules.absolute_seg_CN.input
    output:
        PanCan_sig_SS = results + 'signatures/PanCan_sig/PanCan_sig.SSmatrix.rds'
    params:
        sample_info = config['samp_solutions'],
        def_SC = 'resources/PanCan.xlsx',
        indir = results,
        outdir = results + 'signatures/PanCan_sig/'
    threads: 10
    conda: 'envs/PanCanSig.yaml'
    script: 'scripts/PanCan_sig.R'







