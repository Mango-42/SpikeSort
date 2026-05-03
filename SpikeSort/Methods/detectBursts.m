function [burstInfo, activity] = detectBursts(spikeTimes)

% Inputs:
    % spikeTimes (double[])

% Output:
% Same kind of structure that burstAnalysis or findBursts outputs 
% This will hopefully be a cleaner method than either of them...
%%
burstInfo = struct();

% Raw spike times - get burst numbers
if(~isstruct(spikeTimes))

    burstNum = zeros([1 length(spikeTimes)]);
    changesStart = zeros([1 length(spikeTimes)]);
    changesEnd = zeros([1 length(spikeTimes)]);
    isi = diff(spikeTimes);
    
    if ~isempty(spikeTimes)
    isi = [spikeTimes(1) isi ];
    end
    
    %isi(isi > 1) = 0.1;
    % Look for a cluster with the biggest isi-- likely starts
    eva = evalclusters(isi','kmeans','DaviesBouldin','KList',1:3);
    k = eva.OptimalK;
    
    [labels, C] = kmeans(isi', k);
    [~, idxMin] = min(C);

    changesStart(labels ~= idxMin) = 1;
    
    burstEnds = [(labels ~= idxMin)' 0];
    burstEnds = burstEnds(2:end);


    changesEnd(burstEnds == 1) = 1;
    
    % Label bursts by ISI clustering
    currBurst = 0;
    for i = 1:length(spikeTimes)
        if changesStart(i)
            currBurst = currBurst + 1;
        end
            burstNum(i) = currBurst;
    end

    
end


% Get avg burst analysis stats 
spikesPer = [];
burstFreq = [];
spikeFreq = [];
timeOn = [];
dCycle = [];
startTimes = [];
endTimes = [];
lastBurstStart = 0;

currSpikes = 0;

for i = 1:length(spikeTimes)
    % Burst start

    currSpikes = currSpikes + 1;

    if changesStart(i) == 1
        
        
        currSpikes = 1;
        if lastBurstStart ~= 0
            burstFreq = [burstFreq 1 ./ (spikeTimes(i) - lastBurstStart)];
        end
        lastBurstStart = spikeTimes(i);
    end
   
    % Burst end   
    if changesEnd(i) == 1 && lastBurstStart ~= 0
        
        startTimes = [startTimes lastBurstStart];
        timeOn = [timeOn spikeTimes(i) - lastBurstStart];
        
        try
            dCycle = [dCycle (timeOn(end) ./ (spikeTimes(i + 1) - lastBurstStart))];
        end
        spikesPer = [spikesPer currSpikes];
        spikeFreq = [spikeFreq ((currSpikes-1) ./ timeOn(end))];
        endTimes = [endTimes spikeTimes(i)];
    end

end

burstInfo.spikeTimes = spikeTimes;
burstInfo.burstNum = burstNum;

activity = struct();
% last burst isn't included by default bc not all these fields can be
% completed for it
activity.burstNum = 1:max(burstNum) - 1;
activity.spikesPer = spikesPer;
activity.spikeFreq = spikeFreq;
activity.dCycle = dCycle;
activity.burstFreq = burstFreq;
activity.burstStarts = startTimes; % Indicator so you can match with other continuous data
activity.burstEnds = endTimes;