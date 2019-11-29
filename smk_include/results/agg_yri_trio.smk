
include: '../result_vars.smk'
include: 'yri_father_na19239.smk'
include: 'yri_mother_na19238.smk'
include: 'yri_child_na19240.smk'

localrules: run_yri_trio

rule run_yri_trio:
    input:
        rules.run_yri_father.input,
        rules.run_yri_mother.input,
        rules.run_yri_child.input
    message: 'Creating results for YRI family trio (high diversity population)'