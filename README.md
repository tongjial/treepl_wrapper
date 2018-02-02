# treepl_wrapper
This is a simple TreePL script for automatically estimating time tree.

Three steps in one run
1. run prime step repeatly 100 times to choose the most frequent cv optimal parameters
2. then perform cross validation and find the smallest cv score
3. finally, time tree will be generated using the corresponding smooth value

## usage:
123
'''
chmod 755 treepl_wrapper.sh
./treepl_wrapper.sh configuration treefile label
'''
