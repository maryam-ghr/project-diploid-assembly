
include: 'aux_utilities.smk'
include: 'preprocess_input.smk'
include: 'preprocess_references.smk'
include: 'prepare_custom_references.smk'
include: 'integrative_phasing.smk'
include: 'variant_calling.smk'
include: 'run_assemblies.smk'
include: 'run_alignments.smk'

localrules: master_strandseq_dga_split, \
            write_assembled_fasta_clusters_fofn


"""
Components:
vc_reads = FASTQ file used for variant calling relative to reference
hap_reads = FASTQ file to be used for haplotype reconstruction
sts_reads = FASTQ file used for strand-seq phasing
"""
PATH_STRANDSEQ_DGA_SPLIT = 'diploid_assembly/strandseq_split/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}'
PATH_STRANDSEQ_DGA_SPLIT_PROTECTED = PATH_STRANDSEQ_DGA_SPLIT.replace('{', '{{').replace('}', '}}')


rule master_strandseq_dga_split:
    input:


rule strandseq_dga_split_haplo_tagging:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = FASTQ file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        vcf = 'output/integrative_phasing/' + PATH_INTEGRATIVE_PHASING + '/{hap_reads}.phased.vcf.bgz',
        tbi = 'output/integrative_phasing/' + PATH_INTEGRATIVE_PHASING + '/{hap_reads}.phased.vcf.bgz.tbi',
        bam = 'output/alignments/reads_to_reference/clustered/{sts_reads}/{hap_reads}_map-to_{reference}.psort.sam.bam',
        bai = 'output/alignments/reads_to_reference/clustered/{sts_reads}/{hap_reads}_map-to_{reference}.psort.sam.bam.bai',
        fasta = 'output/reference_assembly/clustered/{sts_reads}/{reference}.fasta',
        seq_info = 'output/reference_assembly/clustered/{sts_reads}/{reference}/sequences/{sequence}.seq',
    output:
        bam = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagged.sam.bam',
        tags = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tags.fq.tsv',
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagging.fq.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagging.fq.rsrc',
    shell:
        'whatshap --debug haplotag --regions {wildcards.sequence} --output {output.bam} ' \
            '--reference {input.fasta} --output-haplotag-list {output.tags} ' \
            '{input.vcf} {input.bam} &> {log}'


rule strandseq_dga_split_haplo_tagging_pacbio_native:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = PacBio native BAM file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        vcf = 'output/integrative_phasing/' + PATH_INTEGRATIVE_PHASING + '/{hap_reads}.phased.vcf.bgz',
        tbi = 'output/integrative_phasing/' + PATH_INTEGRATIVE_PHASING + '/{hap_reads}.phased.vcf.bgz.tbi',
        bam = 'output/alignments/reads_to_reference/clustered/{sts_reads}/{hap_reads}_map-to_{reference}.psort.pbn.bam',
        bai = 'output/alignments/reads_to_reference/clustered/{sts_reads}/{hap_reads}_map-to_{reference}.psort.pbn.bam.bai',
        fasta = 'output/reference_assembly/clustered/{sts_reads}/{reference}.fasta',
        seq_info = 'output/reference_assembly/clustered/{sts_reads}/{reference}/sequences/{sequence}.seq',
    output:
        bam = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagged.pbn.bam',
        tags = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tags.pbn.tsv',
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagging.pbn.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tagging.pbn.rsrc',
    shell:
        'whatshap --debug haplotag --regions {wildcards.sequence} --output {output.bam} ' \
            '--reference {input.fasta} --output-haplotag-list {output.tags} ' \
            '{input.vcf} {input.bam} &> {log}'


rule strandseq_dga_split_haplo_splitting:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = FASTQ file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        fastq = 'input/fastq/complete/{hap_reads}.fastq.gz',
        tags = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tags.fq.tsv',
    output:
        h1 = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.h1.{sequence}.fastq.gz',
        h2 = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.h2.{sequence}.fastq.gz',
        un = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.un.{sequence}.fastq.gz',
        hist = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.rlen-hist.{sequence}.fq.tsv'
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.{sequence}.splitting.fq.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.{sequence}.splitting.fq.rsrc',
    resources:
        mem_per_cpu_mb = 8192,
        mem_total_mb = 8192
    shell:
        'whatshap --debug split --discard-unknown-reads --pigz ' \
            '--output-h1 {output.h1} --output-h2 {output.h2} --output-untagged {output.un} ' \
            '--read-lengths-histogram {output.hist} {input.fastq} {input.tags} &> {log}'


rule strandseq_dga_split_haplo_splitting_pacbio_native:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = PacBio native BAM file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        pbn_bam = 'input/bam/complete/{hap_reads}.pbn.bam',
        pbn_idx = 'input/bam/complete/{hap_reads}.pbn.bam.bai',
        tags = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haplotags/{hap_reads}.{sequence}.tags.pbn.tsv',
    output:
        h1 = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.h1.{sequence}.pbn.bam',
        h2 = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.h2.{sequence}.pbn.bam',
        un = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.un.{sequence}.pbn.bam',
        hist = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.rlen-hist.{sequence}.pbn.tsv'
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.{sequence}.splitting.pbn.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.{sequence}.splitting.pbn.rsrc',
    resources:
        mem_per_cpu_mb = 8192,
        mem_total_mb = 8192
    shell:
        'whatshap --debug split --discard-unknown-reads ' \
            '--output-h1 {output.h1} --output-h2 {output.h2} --output-untagged {output.un} ' \
            '--read-lengths-histogram {output.hist} {input.pbn_bam} {input.tags} &> {log}'


rule strandseq_dga_split_merge_tag_groups:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = FASTQ file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        hap = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.h{haplotype}.{sequence}.fastq.gz',
        un = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.un.{sequence}.fastq.gz',
    output:
        'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{hap_reads}.h{haplotype}-un.{sequence}.fastq.gz',
    wildcard_constraints:
        haplotype = '(1|2)'
    shell:
        'cat {input.hap} {input.un} > {output}'


rule strandseq_dga_split_merge_tag_groups_pacbio_native:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = PacBio native BAM file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    """
    input:
        hap = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.h{haplotype}.{sequence}.pbn.bam',
        un = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.un.{sequence}.pbn.bam',
    output:
        'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.h{haplotype}-un.{sequence}.pbn.bam',
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{hap_reads}.h{haplotype}-un.{sequence}.pbn.mrg.log',
    wildcard_constraints:
        haplotype = '(1|2)'
    shell:
        'bamtools merge -in {input.hap} -in {input.un} -out {output} &> {log}'


# The following merge step is primarily for convenience, i.e. for pushing
# the assembled sequence as single FASTA file into the evaluation part
# of the pipeline (e.g., QUAST-LG)

def collect_assembled_sequence_files(wildcards):
    """
    """
    reference_folder = os.path.join('output/reference_assembly/clustered', wildcards.sts_reads)
    seq_output_dir = checkpoints.create_assembly_sequence_files.get(folder_path=reference_folder,
                                                                    reference=wildcards.reference).output[0]
    checkpoint_wildcards = glob_wildcards(os.path.join(seq_output_dir, '{sequence}.seq'))

    seq_files = expand('output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fasta/split/{hap_reads}-{assembler}.{hap}.{sequence}.fasta',
                        var_caller=wildcards.var_caller,
                        gq=wildcards.gq,
                        qual=wildcards.qual,
                        reference=wildcards.reference,
                        vc_reads=wildcards.vc_reads,
                        sts_reads=wildcards.sts_reads,
                        hap_reads=wildcards.hap_reads,
                        assembler=wildcards.assembler,
                        hap=wildcards.hap,
                        sequence=checkpoint_wildcards.sequence)
    return sorted(seq_files)


rule write_assembled_fasta_clusters_fofn:
    input:
        cluster_fastas = collect_assembled_sequence_files
    output:
        fofn = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fasta/{hap_reads}-{assembler}.{hap}.fofn',
    run:
        # follow same example as merge strand-seq BAMs in module prepare_custom_references
        fasta_files = collect_assembled_sequence_files(wildcards)

        with open(output.fofn, 'w') as dump:
            for file_path in sorted(fasta_files):
                if not os.path.isfile(file_path):
                    if os.path.isdir(file_path):
                        # this is definitely wrong
                        raise AssertionError('Expected file path for cluster FASTA merge, but received directory: {}'.format(file_path))
                    import sys
                    sys.stderr.write('\nWARNING: File missing, may not be created yet - please check: {}\n'.format(file_path))
                _ = dump.write(file_path + '\n')


rule strandseq_dga_split_merge_sequences:
    """
    """
    input:
        fofn = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fasta/{hap_reads}-{assembler}.{hap}.fofn'
    output:
         'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fasta/{hap_reads}-{assembler}.{hap}.fasta'
    params:
        cluster_fastas = lambda wildcards, input: load_fofn_file(input)
    shell:
        'cat {params.cluster_fastas} > {output}'
