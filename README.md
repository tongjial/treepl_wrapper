# Treepl_wrapper
This is a simple TreePL script for automatically estimating time tree.

Three steps in one run
1. run prime step repeatly 100 times to choose the most frequent cv optimal parameters
2. then perform cross validation and find the smallest cv score
3. finally, time tree will be generated using the corresponding smooth value

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
mrca = nodename taxa1 taxa2
min = nodename 48.60
max = nodename 83.60
nthreads = 2
```

## Reference
Smith, S.A. and O’Meara, B.C., 2012. treePL: divergence time estimation using penalized likelihood for large phylogenies. Bioinformatics, 28(20), pp.2689-2690.
