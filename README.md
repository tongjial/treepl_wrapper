# TreePL_wrapper
An automatic pipeline for estimating time tree using TreePL.

This script includes three steps in one run
1. Conduct the prime step 100 times to choose the most frequent cv optimal parameter;
2. Perform cross validation and find the smooth value with the smallest cv score;
3. Generate the time tree using the optimized smooth value.

## Prerequisite
* [TreePL](https://github.com/blackrim/treePL)

## Usage
```
chmod 755 treepl_wrapper.sh
./treepl_wrapper.sh configuration treefile label
```
Make sure treePL in your environment and treefile must be a single rooted tree

Configuration file example
```
numsites = 2882628
mrca = nodename1 taxa1 taxa2
min = nodename1 48.60
max = nodename1 83.60
mrca = nodename2 taxa3 taxa4
min = nodename2 24.10
max = nodename2 51.70
nthreads = 2
```

## Reference
Smith, S.A. and O’Meara, B.C., 2012. treePL: divergence time estimation using penalized likelihood for large phylogenies. Bioinformatics, 28(20), pp.2689-2690.
