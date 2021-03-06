
localrules: master_run_alignments,
            derive_minimap_parameter_preset,
            derive_pbmm2_parameter_preset_pbn,
            derive_pbmm2_parameter_preset_fastq


rule master_run_alignments:
    input:
        []


rule derive_minimap_parameter_preset:
    input:
        '{filepath}.fastq.gz'
    output:
        '{filepath}.preset.minimap'
    run:
        import os
        preset = ' -x '
        path, filename = os.path.split(input[0])
        tech_spec = filename.split('_')[2]
        if tech_spec.startswith('ont'):
            preset += 'map-ont --secondary=no'
        elif '-clr' in tech_spec:
            # as per recommendation in help
            preset += 'map-pb -H --secondary=no'
        elif '-ccs' in tech_spec:
            # https://github.com/lh3/minimap2/issues/325
            preset += 'asm20 --secondary=no'
        else:
            raise ValueError('No minimap preset for file: {}'.format(filename))

        # This is special for alignment before Racon polishing;
        # note that even for CCS reads, the PacBio preset is used
        # Recommended by Aaron Wenger
        if all([x in path for x in ['diploid_assembly', 'draft', 'haploid_fastq']]):
            preset = ' -x map-pb --eqx -m 5000 --secondary=no '

        with open(output[0], 'w') as dump:
            _ = dump.write(preset)


rule derive_pbmm2_parameter_preset_pbn:
    """
    TODO (see below)
    https://github.com/PacificBiosciences/pbmm2
    The --min-length option is a custom addition
    """
    input:
        '{filepath}.pbn.bam'
    output:
        '{filepath}.preset.pbmm2'
    run:
        import os
        filename = os.path.basename(input[0])
        tech_spec = filename.split('_')[2]
        preset = ''
        if '-clr' in tech_spec:
            preset = 'SUBREAD --min-length 5000 '
        elif '-ccs' in tech_spec:
            preset = 'CCS --min-length 5000 '
        else:
            raise ValueError('No pbmm2 preset for file: {}'.format(filename))

        with open(output[0], 'w') as dump:
            _ = dump.write(preset)


rule derive_pbmm2_parameter_preset_fastq:
    """
    TODO (see above)
    https://github.com/PacificBiosciences/pbmm2
    The --min-length option is a custom addition
    """
    input:
        '{filepath}.fastq.gz'
    output:
        '{filepath}.preset.pbmm2'
    run:
        import os
        filename = os.path.basename(input[0])
        tech_spec = filename.split('_')[2]
        preset = ''
        if '-clr' in tech_spec:
            preset = 'SUBREAD --min-length 5000 '
        elif '-ccs' in tech_spec:
            preset = 'CCS --min-length 5000 '
        else:
            raise ValueError('No pbmm2 preset for file: {}'.format(filename))

        with open(output[0], 'w') as dump:
            _ = dump.write(preset)


rule minimap_reads_to_reference_alignment:
    input:
        reads = 'input/fastq/{sample}.fastq.gz',
        preset = 'input/fastq/{sample}.preset.minimap',
        reference = 'output/reference_assembly/{folder_path}/{reference}.fasta'
    output:
        'output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.psort.sam.bam'
    log:
        minimap = 'log/output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.minimap.log',
        st_sort = 'log/output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.st-sort.log',
        st_view = 'log/output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.st-view.log',
    benchmark:
        os.path.join('run/output/alignments/reads_to_reference/{folder_path}',
                     '{sample}_map-to_{reference}' + '.t{}.rsrc'.format(config['num_cpu_high']))
    conda:
        '../environment/conda/conda_biotools.yml'
    wildcard_constraints:
        sample = CONSTRAINT_NANOPORE_SAMPLES
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int((55296 * attempt) / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: 55296 * attempt,
        runtime_hrs = 71,
        mem_sort_mb = 8192
    params:
        individual = lambda wildcards: wildcards.sample.split('_')[0],
        preset = load_preset_file,
        discard_flag = config['minimap_readref_aln_discard'],
        tempdir = lambda wildcards: os.path.join(
                                        'temp', 'minimap', wildcards.folder_path,
                                        wildcards.sample, wildcards.reference)
    shell:
        'rm -rfd {params.tempdir} ; mkdir -p {params.tempdir} && '
        'minimap2 -t {threads} {params.preset} -a '
            '-R "@RG\\tID:1\\tSM:{params.individual}" '
            '{input.reference} {input.reads} 2> {log.minimap} | '
            'samtools sort -m {resources.mem_sort_mb}M -T {params.tempdir} 2> {log.st_sort} | '
            'samtools view -b -F {params.discard_flag} /dev/stdin > {output} 2> {log.st_view}'


rule pbmm2_reads_to_reference_alignment_pacbio_native:
    input:
        reads = 'input/bam/{sample}.pbn.bam',
        preset = 'input/bam/{sample}.preset.pbmm2',
        reference = 'output/reference_assembly/{folder_path}/{reference}.fasta'
    output:
        bam = 'output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.psort.pbn.bam',
    log:
        'log/output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.pbn.log'
    benchmark:
        'run/output/alignments/reads_to_reference/{{folder_path}}/{{sample}}_map-to_{{reference}}.pbmm2.t{}.rsrc'.format(config['num_cpu_high'])
    conda:
        '../environment/conda/conda_pbtools.yml'
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int((110592 if attempt <= 1 else 188416) / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: 110592 if attempt <= 1 else 188416,
        runtime_hrs = 71
    params:
        align_threads = config['num_cpu_high'] - 2,
        sort_threads = 2,
        preset = load_preset_file,
        individual = lambda wildcards: wildcards.sample.split('_')[0],
        tempdir = lambda wildcards: os.path.join(
                                        'temp', 'pbmm2', wildcards.folder_path,
                                        wildcards.sample, wildcards.reference)
    shell:
        'TMPDIR={params.tempdir} '
        'pbmm2 align --log-level INFO --sort --sort-memory {resources.mem_per_cpu_mb}M --no-bai '
            ' --alignment-threads {params.align_threads} --sort-threads {params.sort_threads} '
            ' --preset {params.preset} --sample {params.individual} '
            ' {input.reference} {input.reads} {output.bam} &> {log}'


rule pbmm2_reads_to_reference_alignment_pacbio_fastq:
    input:
        reads = 'input/fastq/{sample}.fastq.gz',
        preset = 'input/fastq/{sample}.preset.pbmm2',
        reference = 'output/reference_assembly/{folder_path}/{reference}.fasta'
    output:
        bam = 'output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.psort.sam.bam',
    log:
        'log/output/alignments/reads_to_reference/{folder_path}/{sample}_map-to_{reference}.pbmm2.log'
    benchmark:
        'run/output/alignments/reads_to_reference/{{folder_path}}/{{sample}}_map-to_{{reference}}.pbmm2.t{}.rsrc'.format(config['num_cpu_high'])
    conda:
        '../environment/conda/conda_pbtools.yml'
    wildcard_constraints:
        sample = CONSTRAINT_PACBIO_SAMPLES
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int((110592 if attempt <= 1 else 188416) / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: 110592 if attempt <= 1 else 188416,
        runtime_hrs = 71
    params:
        align_threads = config['num_cpu_high'] - 2,
        sort_threads = 2,
        preset = load_preset_file,
        individual = lambda wildcards: wildcards.sample.split('_')[0],
        tempdir = lambda wildcards: os.path.join(
                                        'temp', 'pbmm2', wildcards.folder_path,
                                        wildcards.sample, wildcards.reference)
    shell:
        'TMPDIR={params.tempdir} '
        'pbmm2 align --log-level INFO --sort --sort-memory {resources.mem_per_cpu_mb}M --no-bai '
            ' --alignment-threads {params.align_threads} --sort-threads {params.sort_threads} '
            ' --preset {params.preset} --rg "@RG\\tID:1\\tSM:{params.individual}" --sample {params.individual} '
            ' {input.reference} {input.reads} {output.bam} &> {log}'


def select_bwa_index(wildcards):

    sts_individual = wildcards.sts_reads.split('_')[0]
    ref_individual = wildcards.reference.split('_')[0]

    if sts_individual != ref_individual:
        raise ValueError('Mixed individual match (bwa index): {}'.format(wildcards))

    # make sure that this gives only a result for the rule bwa_strandseq_to_reference_alignment,
    # should be ensured via output file naming of the two bwa rules, but better safe than sorry...
    expected_keys = {'sts_reads', 'reference', 'individual', 'sample_id'}
    received_keys = set(dict(wildcards).keys())
    if len(received_keys - expected_keys) != 0:
        raise ValueError('select_bwa_index received unexpected input: '
                         '{} vs {}'.format(sorted(expected_keys), sorted(received_keys)))

    if '_nhr-' in wildcards.reference:
        # non-haplotype resolved assembly / collapsed assembly
        idx = 'output/reference_assembly/non-hap-res/{}/bwa_index/{}.bwt'.format(wildcards.reference, wildcards.reference)
    elif '_scV{}-'.format(config['git_commit_version']) in wildcards.reference:
        idx = 'output/reference_assembly/clustered/{}/{}/bwa_index/{}.bwt'.format(wildcards.sts_reads, wildcards.reference, wildcards.reference)
    else:
        raise ValueError('Unexpected reference type: {} / {}'.format(wildcards.reference, wildcards))
    return idx


rule bwa_strandseq_to_reference_alignment:
    input:
        mate1 = 'input/fastq/{sts_reads}/{individual}_{sample_id}_1.fastq.gz',
        mate2 = 'input/fastq/{sts_reads}/{individual}_{sample_id}_2.fastq.gz',
        ref_index = select_bwa_index,
        sts_reads = 'input/fastq/{sts_reads}.fofn'
    output:
        bam = 'output/alignments/strandseq_to_reference/{reference}/{sts_reads}/temp/aln/{individual}_{sample_id}.filt.sam.bam'
    log:
        bwa = 'log/output/alignments/strandseq_to_reference/{reference}/{sts_reads}/{individual}_{sample_id}.bwa.log',
        samtools = 'log/output/alignments/strandseq_to_reference/{reference}/{sts_reads}/{individual}_{sample_id}.samtools.log',
    benchmark:
        os.path.join('run/output/alignments/strandseq_to_reference/{reference}/{sts_reads}',
                     '{individual}_{sample_id}' + '.t{}.rsrc'.format(config['num_cpu_low']))
    conda:
        '../environment/conda/conda_biotools.yml'
    threads: config['num_cpu_low']
    resources:
        mem_per_cpu_mb = int(8192 / config['num_cpu_low']),
        mem_total_mb = 8192
    params:
        idx_prefix = lambda wildcards, input: input.ref_index.rsplit('.', 1)[0],
        discard_flag = config['bwa_strandseq_aln_discard']
    shell:
        'bwa mem -t {threads}'
            ' -R "@RG\\tID:{wildcards.individual}_{wildcards.sample_id}\\tPL:Illumina\\tSM:{wildcards.individual}"'
            ' -v 2 {params.idx_prefix} {input.mate1} {input.mate2} 2> {log.bwa} | '
            ' samtools view -b -F {params.discard_flag} /dev/stdin > {output.bam} 2> {log.samtools}'


rule bwa_strandseq_to_haploid_assembly_alignment:
    input:
        mate1 = 'input/fastq/{sts_reads}/{individual}_{library_id}_1.fastq.gz',
        mate2 = 'input/fastq/{sts_reads}/{individual}_{library_id}_2.fastq.gz',
        ref_index = os.path.join('output', 'diploid_assembly/strandseq_{hap_assm_mode}/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}',
                                 'polishing/{pol_reads}/haploid_assembly/{hap_reads}-{hap_assembler}.{hap}.{pol_pass}/bwa_index/{hap_reads}-{hap_assembler}.{hap}.{pol_pass}.bwt'),
        sts_reads = 'input/fastq/{sts_reads}.fofn'
    output:
        bam = os.path.join(
            'output/alignments/strandseq_to_phased_assembly',
            'strandseq_{hap_assm_mode}/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}/{pol_reads}',
            '{hap_reads}-{hap_assembler}.{hap}.{pol_pass}',
            'temp/aln/{individual}_{library_id}.filt.sam.bam')
    log:
        bwa = os.path.join(
            'log', 'output/alignments/strandseq_to_phased_assembly',
            'strandseq_{hap_assm_mode}/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}/{pol_reads}',
            '{hap_reads}-{hap_assembler}.{hap}.{pol_pass}',
            'temp/aln/{individual}_{library_id}.bwa.log'),
        samtools = os.path.join(
            'log', 'output/alignments/strandseq_to_phased_assembly',
            'strandseq_{hap_assm_mode}/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}/{pol_reads}',
            '{hap_reads}-{hap_assembler}.{hap}.{pol_pass}',
            'temp/aln/{individual}_{library_id}.samtools.log')
    benchmark:
        os.path.join(
            'run', 'output/alignments/strandseq_to_phased_assembly',
            'strandseq_{hap_assm_mode}/{var_caller}_QUAL{qual}_GQ{gq}/{reference}/{vc_reads}/{sts_reads}/{pol_reads}',
            '{hap_reads}-{hap_assembler}.{hap}.{pol_pass}',
            'temp/aln/{individual}_{library_id}.bwa' + '.t{}.rsrc'.format(config['num_cpu_low']))
    conda:
        '../environment/conda/conda_biotools.yml'
    threads: config['num_cpu_low']
    resources:
        mem_per_cpu_mb = int(8192 / config['num_cpu_low']),
        mem_total_mb = 8192
    params:
        idx_prefix = lambda wildcards, input: input.ref_index.rsplit('.', 1)[0],
        discard_flag = config['bwa_strandseq_aln_discard']
    shell:
        'bwa mem -t {threads}'
            ' -R "@RG\\tID:{wildcards.individual}_{wildcards.library_id}\\tPL:Illumina\\tSM:{wildcards.individual}"'
            ' -v 2 {params.idx_prefix} {input.mate1} {input.mate2} 2> {log.bwa} | '
            ' samtools view -b -F {params.discard_flag} /dev/stdin > {output.bam} 2> {log.samtools}'


rule minimap_racon_polish_alignment_pass1:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = FASTQ file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    pol_reads = FASTQ file used for Racon contig polishing
    """
    input:
        reads = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{pol_reads}.{hap}.{sequence}.fastq.gz',
        preset = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{pol_reads}.{hap}.{sequence}.preset.minimap',
        contigs = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_assembly/{hap_reads}-{assembler}.{hap}.{sequence}.fasta',
    output:
        sam = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p1.psort.sam',
    log:
        minimap = 'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p1.minimap.log',
        st_sort = 'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p1.st-sort.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT_PROTECTED + '/polishing/alignments/{{pol_reads}}_map-to_{{hap_reads}}-{{assembler}}.{{hap}}.{{sequence}}.racon-p1.t{}.rsrc'.format(config['num_cpu_high'])
    conda:
        '../environment/conda/conda_biotools.yml'
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int(attempt * 16384 / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: attempt * 16384,
        mem_sort_mb = 4096,
        runtime_hrs = 3
    params:
        individual = lambda wildcards: wildcards.hap_reads.split('_')[0],
        preset = load_preset_file,
        discard_flag = config['minimap_racon_aln_discard'],
        min_qual = config['minimap_racon_aln_min_qual'],
        tempdir = lambda wildcards: os.path.join(
                                      'temp', 'minimap', PATH_STRANDSEQ_DGA_SPLIT,
                                      wildcards.pol_reads, wildcards.hap_reads,
                                      wildcards.assembler, wildcards.hap, wildcards.sequence, 'pass1')
    shell:
        'rm -rfd {params.tempdir} ; mkdir -p {params.tempdir} && '
        'minimap2 -t {threads} -a {params.preset} -R "@RG\\tID:1\\tSM:{params.individual}" '
            ' {input.contigs} {input.reads} 2> {log.minimap} | '
            ' samtools sort -m {resources.mem_sort_mb}M -T {params.tempdir} 2> {log.st_sort} | '
            ' samtools view -q {params.min_qual} -F {params.discard_flag} /dev/stdin > {output.sam}'


rule minimap_racon_polish_alignment_pass2:
    """
    vc_reads = FASTQ file used for variant calling relative to reference
    hap_reads = FASTQ file to be used for haplotype reconstruction
    sts_reads = FASTQ file used for strand-seq phasing
    pol_reads = FASTQ file used for Racon contig polishing
    """
    input:
        reads = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{pol_reads}.{hap}.{sequence}.fastq.gz',
        preset = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_fastq/{pol_reads}.{hap}.{sequence}.preset.minimap',
        contigs = os.path.join('output', PATH_STRANDSEQ_DGA_SPLIT, 'polishing/{pol_reads}/haploid_assembly/{hap_reads}-{assembler}.{hap}.{sequence}.racon-p1.fasta')
    output:
        sam = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p2.psort.sam',
    log:
        minimap = 'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p2.minimap.log',
        st_sort = 'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p2.st-sort.log',
    benchmark:
        os.path.join(
            'run/output', PATH_STRANDSEQ_DGA_SPLIT,
            'polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.racon-p2.' + 't{}.rsrc'.format(config['num_cpu_high'])
        )
    conda:
        '../environment/conda/conda_biotools.yml'
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int(attempt * 16384 / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: attempt * 16384,
        mem_sort_mb = 4096,
        runtime_hrs = 3
    params:
        individual = lambda wildcards: wildcards.hap_reads.split('_')[0],
        preset = load_preset_file,
        discard_flag = config['minimap_racon_aln_discard'],
        min_qual = config['minimap_racon_aln_min_qual'],
        tempdir = lambda wildcards: os.path.join(
                                      'temp', 'minimap', PATH_STRANDSEQ_DGA_SPLIT,
                                      wildcards.pol_reads, wildcards.hap_reads,
                                      wildcards.assembler, wildcards.hap, wildcards.sequence, 'pass2')
    shell:
        'rm -rfd {params.tempdir} ; mkdir -p {params.tempdir} && '
        'minimap2 -t {threads} -a {params.preset} -R "@RG\\tID:1\\tSM:{params.individual}" '
            ' {input.contigs} {input.reads} 2> {log.minimap} | '
            ' samtools sort -m {resources.mem_sort_mb}M -T {params.tempdir} 2> {log.st_sort} | '
            ' samtools view -q {params.min_qual} -F {params.discard_flag} /dev/stdin > {output.sam}'


rule pbmm2_arrow_polish_alignment_pass1:
    input:
        reads = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{pol_reads}.{hap}.{sequence}.pbn.bam',
        preset = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_bam/{pol_reads}.{hap}.{sequence}.preset.pbmm2',
        contigs = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/draft/haploid_assembly/{hap_reads}-{assembler}.{hap}.{sequence}.fasta',
    output:
        bam = 'output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.arrow-p1.psort.pbn.bam',
    log:
        'log/output/' + PATH_STRANDSEQ_DGA_SPLIT + '/polishing/alignments/{pol_reads}_map-to_{hap_reads}-{assembler}.{hap}.{sequence}.arrow-p1.psort.log',
    benchmark:
        'run/output/' + PATH_STRANDSEQ_DGA_SPLIT_PROTECTED + '/polishing/alignments/{{pol_reads}}_map-to_{{hap_reads}}-{{assembler}}.{{hap}}.{{sequence}}.arrow-p1.psort.t{}.rsrc'.format(config['num_cpu_high'])
    conda:
        '../environment/conda/conda_pbtools.yml'
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int(attempt * 16384 / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: attempt * 16384,
        runtime_hrs = 4
    params:
        align_threads = config['num_cpu_high'] - 2,
        sort_threads = 2,
        preset = load_preset_file,
        individual = lambda wildcards: wildcards.hap_reads.split('_')[0],
        tempdir = lambda wildcards: os.path.join(
                                        'temp', 'pbmm2', PATH_STRANDSEQ_DGA_SPLIT,
                                        wildcards.pol_reads, wildcards.hap_reads,
                                        wildcards.assembler, wildcards.hap, wildcards.sequence)
    shell:
        'TMPDIR={params.tempdir} '
        'pbmm2 align --log-level INFO --sort --sort-memory {resources.mem_per_cpu_mb}M --no-bai '
            ' --alignment-threads {params.align_threads} --sort-threads {params.sort_threads} '
            ' --preset {params.preset} --sample {params.individual} '
            ' {input.contigs} {input.reads} {output.bam} &> {log}'


rule minimap_contig_to_known_reference_alignment:
    input:
        contigs = 'output/{folder_path}/{file_name}.fasta',
        #preset = 'input/fastq/{sample}.preset.minimap',
        reference = 'references/assemblies/{aln_reference}.fasta'
    output:
        'output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.psort.sam.bam'
    log:
        minimap = 'log/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.minimap.log',
        st_sort = 'log/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.st-sort.log',
        st_view = 'log/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.st-view.log',
    benchmark:
        '.'.join(['run/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}', 't{}'.format(config['num_cpu_high']), 'rsrc'])
    conda:
        '../environment/conda/conda_biotools.yml'
    threads: config['num_cpu_high']
    resources:
        mem_per_cpu_mb = lambda wildcards, attempt: int((16384 + 32768 * attempt) / config['num_cpu_high']),
        mem_total_mb = lambda wildcards, attempt: 16384 + 32768 * attempt,
        runtime_hrs = 71,
        mem_sort_mb = 8192
    params:
        individual = lambda wildcards: wildcards.file_name.split('_')[0],
        readgroup_id = lambda wildcards: wildcards.file_name.replace('.', '_'),
        discard_flag = config['minimap_contigref_aln_discard'],
        tempdir = lambda wildcards: os.path.join(
                                        'temp', 'minimap', wildcards.folder_path,
                                        wildcards.file_name, wildcards.aln_reference)
    shell:
        'rm -rfd {params.tempdir} ; mkdir -p {params.tempdir} && '
        'minimap2 -t {threads} '
            '--secondary=no --eqx -Y -ax asm20 -m 10000 -z 10000,50 -r 50000 --end-bonus=100 -O 5,56 -E 4,1 -B 5 '
            '-R "@RG\\tID:{params.readgroup_id}\\tSM:{params.individual}" '
            '{input.reference} {input.contigs} 2> {log.minimap} | '
            'samtools sort -m {resources.mem_sort_mb}M -T {params.tempdir} 2> {log.st_sort} | '
            'samtools view -b -F {params.discard_flag} /dev/stdin > {output} 2> {log.st_view}'


rule dump_contig_to_reference_alignment_to_bed:
    """
    Needed to create SaaRclust diagnostic plots - see create_plots module
    """
    input:
        'output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.psort.sam.bam'
    output:
        'output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.bed'
    log:
        'log/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.dump-bed.log'
    benchmark:
        'run/output/alignments/contigs_to_reference/{folder_path}/{file_name}_map-to_{aln_reference}.dump-bed.rsrc'
    conda:
        '../environment/conda/conda_biotools.yml'
    resources:
        runtime_hrs = lambda wildcards, attempt: attempt,
        mem_total_mb = 2048,
        mem_per_cpu_mb = 2048
    shell:
        'bedtools bamtobed -i {input} > {output} 2> {log}'
