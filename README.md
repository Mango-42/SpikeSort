# SpikeSort
Senior thesis project to automate spike sorting for crustacean STG
Migrated from my main lab work and tools repository 5/3
UPDATE: Use the Marder Lab version of this repository -- I will be porting things there in the next weeks. 

# Documented Use
Clone the repository and open in MATLAB. 
Built and tested on MATLAB 2022b
For automatic metadata mapping and experiment opening, add entries to Methods/pathfinder.m and Methods/metadataMaster.m
This will let you load in an experiment with channels mapped automatically, just from notebook and page. 

# Current Work
- Need default manual channel mapping
- Some layout changes still - overlapping panels on resize
- Check and debug for forward MATLAB version compatibility
- Functionality to set all spikes in a channel across all files to a certain neuron
