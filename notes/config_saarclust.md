# Configuration for SaaRclust

Sent by David via e-mail on 2019-09-18

Relevance:
  - config parameters for standard SaaRclust run
  - important: see also fixed parameters in Snakemake config
  - parameters fixed for reproducibility, obtaining 24 clusters per sample

```
library(SaaRclust)
bamfolder <- "/[...]/Saarclust_project/alignments_canu_HIFI/HG00733/"
assembly.fasta <- "/[...]/Saarclust_project/alignments_canu_HIFI/Assembly/HG00733.2x_racon.fasta"
scaffoldDenovoAssembly(bamfolder = bamfolder,
                       outputfolder = "/[...]/Saarclust_project/alignments_canu_HIFI/HG00733/SaaRclust_results",
                       store.data.obj = TRUE,
                       reuse.data.obj = TRUE,
                       pairedEndReads = TRUE,
                       bin.size = 100000,
                       step.size = 50000,
                       min.contig.size = 100000,
                       assembly.fasta = assembly.fasta,
                       concat.fasta = FALSE,
                       num.clusters = 100,
                       remove.always.WC = FALSE)


#============== SaaRclust configuration file ===============#

[SaaRclust]
min.contig.size  =  100000 
pairedEndReads  =  TRUE 
bin.size  =  100000
step.size  =  50000 
store.data.obj  =  TRUE 
reuse.data.obj  =  TRUE 
num.clusters  =  100 
alpha  =  0.1 
best.prob  =  1 
prob.th  =  0 
ord.method  =  'TSP' 
assembly.fasta  =  '/[...]/Saarclust_project/alignments_canu_HIFI/Assembly/HG00733.2x_racon.fasta' 
concat.fasta  =  TRUE 
z.limit  =  3 
remove.always.WC  =  FALSE 

```

Update sent by David via e-mail on 2019-10-27

```
scaffoldDenovoAssembly(bamfolder = ...,
                       outputfolder = "...",
                       store.data.obj = TRUE,
                       reuse.data.obj = TRUE,
                       pairedEndReads = TRUE,
                       bin.size = 100000,
                       step.size = 50000,
                       bin.method = 'dynamic',
                       min.contig.size = 100000,
                       assembly.fasta = assembly.fasta,
                       concat.fasta = FALSE,
                       num.clusters = 100,
                       remove.always.WC = TRUE,
                       mask.regions = FALSE)
```

Update sent by David via e-mail on 2019-10-31

```
scaffoldDenovoAssembly(bamfolder = bamfolder,
                       outputfolder = "...",
                       store.data.obj = TRUE,
                       reuse.data.obj = TRUE,
                       pairedEndReads = TRUE,
                       bin.size = 500000,
                       step.size = 50000,
                       prob.th = 0.5,
                       bin.method = 'dynamic',
                       min.contig.size = 100000,
                       assembly.fasta = assembly.fasta,
                       concat.fasta = FALSE,
                       num.clusters = 100,
                       remove.always.WC = TRUE,
                       mask.regions = FALSE)
```

Update sent by David via e-mail on 2019-11-01
Based on comment in e-mail and below name of output folder,
switch to "fixed" binning strategy

```
scaffoldDenovoAssembly(bamfolder = bamfolder,
                       outputfolder = "[...]/HG00733/SaaRclust_results_fixed500K_probTh0.5",
                       store.data.obj = TRUE,
                       reuse.data.obj = TRUE,
                       pairedEndReads = TRUE,
                       bin.size = 500000,
                       step.size = 50000,
                       prob.th=0.5,
                       bin.method = 'dynamic', (<-- switch to fixed)
                       min.contig.size = 100000,
                       assembly.fasta = assembly.fasta,
                       concat.fasta = FALSE,
                       num.clusters = 100,
                       remove.always.WC = TRUE,
                       mask.regions = FALSE)
```

Update sent by David via e-mail on 2019-11-08

```
## So far the preferred params for SaaRclust
scaffoldDenovoAssembly(bamfolder = bamfolder,
                       outputfolder = <>,
                       store.data.obj = TRUE,
                       reuse.data.obj = TRUE,
                       pairedEndReads = TRUE,
                       bin.size = 200000,
                       step.size = 200000,
                       prob.th = 0.25,
                       bin.method = 'dynamic',
                       min.contig.size = 100000,
                       assembly.fasta = assembly.fasta,
                       concat.fasta = TRUE,
                       num.clusters = 100,
                       remove.always.WC = TRUE,
                       mask.regions = FALSE)

```