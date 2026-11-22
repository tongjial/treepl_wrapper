# TreePL_wrapper
An automatic pipeline for estimating time trees using TreePL.

This script includes three steps in a single run:
1. Conduct the prime step 100 times to obtain the most frequently occurring optimal cross-validation (cv) parameters;
2. Perform cross-validation and find the smoothing value with the smallest cv score;
3. Generate the time tree using the optimized smoothing value.

## Prerequisite
* [TreePL](https://github.com/blackrim/treePL) (the `treePL` executable must be in `PATH`, or set `TREEPL_BIN`)
* bash, awk, sed and coreutils

## Usage
```
chmod 755 treepl_wrapper.sh
./treepl_wrapper.sh [options] configuration treefile label
```

Options:
* `-h`, `--help`: show the usage and exit
* `--version`: show the version and exit

Make sure treePL in your environment and treefile must be a single rooted tree.
This tree should be a best ML tree with meaningful branch length (substitutions per site per year).
Of course, you can also use a bunch of bootstrap trees to obtain confidence interval.
A better way is to concatenate the best ML tree and bootstrap trees into a single file, and list the best ML tree first.

`label` is used to name the output files. It must not be empty and must not contain a path separator (`/`) or `=`.
File paths containing spaces are supported, but the tree file path must not contain `=` (treePL splits configuration lines on `=`).

Configuration file example
```
numsites = 2882628
mrca = nodename1 taxa1 taxa2
min = nodename1 48.60
max = nodename1 83.60
mrca = nodename2 taxa3 taxa4
min = nodename2 24.10
max = nodename2 51.70
nthreads = 8
```
Do not put `treefile`, `prime`, `cv*`, `smoothing` or `outfile` lines in the configuration file; the script adds them.

Note: 
The mrca calibration nodes should only select the highly supported ones. 
Given all descendent names of each mrca in configure file is recommended.

## Minimal example
```
$ cat test.tre
(((a:0.3,b:0.3):0.2,((c:0.2,d:0.2):0.1,e:0.3):0.2):0.1,(f:0.4,g:0.4):0.2):0.1;
$ cat test.conf
numsites = 10000
mrca = rt a f
mrca = c1 a b
min = c1 3
max = c1 4
min = rt 10
max = rt 10
nthreads = 2
$ ./treepl_wrapper.sh test.conf test.tre demo
$ cat treepl_demo.tre
```
Use `TREEPL_PRIME_RUNS=5 ./treepl_wrapper.sh test.conf test.tre demo` for a quick trial run.

## Output files
All intermediate files (`configure_prime_<label>`, `prime_<label>`, `configure_cv_<label>`, `cv_<label>`, `configure_smooth_<label>`, `out_dates.tre`, ...) are written to a temporary directory that is removed when the script exits, so existing files with the same names in the current directory are never touched.
Only the following files are written to the current directory (existing files with these names are overwritten):

| File | Content |
| --- | --- |
| `treepl_<label>.tre` | dated tree(s) estimated with the selected smoothing value |
| `treepl_<label>.tre.r8s` | the same tree(s) in r8s style, if written by treePL |
| `prime_<label>.log` | treePL output of all prime runs |
| `cv_<label>.log` | treePL output of the cross-validation step |
| `final_<label>.log` | treePL output of the final smoothing step |

The log files are also copied back when the script fails, to help with debugging.

## Environment variables
| Variable | Default | Description |
| --- | --- | --- |
| `TREEPL_BIN` | `treePL` | treePL executable (name in `PATH` or a path) |
| `TREEPL_PRIME_RUNS` | `100` | number of prime runs |
| `TREEPL_CV_START` | `0.0001` | `cvstart` of the cross-validation (must be > 0) |
| `TREEPL_CV_STOP` | `10000` | `cvstop` of the cross-validation (must be > 0) |
| `TREEPL_KEEP_TMP` | `0` | set to `1` to keep the temporary directory (its path is printed) |
| `TMPDIR` | `/tmp` | parent directory of the temporary directory |

## Exit codes
| Code | Meaning |
| --- | --- |
| 0 | success |
| 1 | usage or environment error (wrong arguments, invalid label or variable, treePL not found) |
| 2 | configuration file or tree file not found |
| 3 | cross-validation failed (treePL error, cv output missing, empty or without a valid smoothing value) |
| 4 | prime step failed (treePL error, or opt/optad/optcvad could not be parsed) |
| 5 | smoothing step failed (treePL error, or no dated tree written) |

Error messages are printed to stderr.

## Reference
Smith, S.A. and O’Meara, B.C., 2012. treePL: divergence time estimation using penalized likelihood for large phylogenies. Bioinformatics, 28(20), pp.2689-2690.
