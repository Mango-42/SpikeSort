function [spikeInfo, onlyAmp] = findSpikeChanges(v, varargin)
%% Description: Look for changes in spike patterns
% Nonspecific detection of burst starts based on time and amplitude

% Does not account for concurrent bursts (i.e. LG, gastric mill at the same time as
% pyloric), so you'll have to rely on other factors in sortSpikes for
% that

% Inputs:
    % v (double []): voltage trace
    % spikeTimes (double []) - optional; your spike times if known, else
    % will call to detect 

% Outputs:
    % spikeInfo (struct) with fields:
        % spikeTimes (double [])
        % burstNum (double []) paired with spike time 


%% Get spike times and set params
Fs = 10^4;
rng(1)
useAmpChanges = 0;

% If you pass in spikes as a secondary argument, assume this IS the set of
% spikes to use (prefiltered)
if nargin  > 1
    [spikeTimes] = varargin{1};
else
    [spikeTimes] = getExtraSpikes(v);
end

if isempty(spikeTimes) 
    spikeInfo = struct();
    spikeInfo.spikeTimes = [];
    spikeInfo.burstNum = [];
    return
end

v = reshape(v,[1,length(v)]);
spikeTimes = reshape(spikeTimes,[1,length(spikeTimes)]);

% Set up an array to track which spikes and likely starting new bursts
changes = zeros([1 length(spikeTimes)]);

%% First look for potential burst starts and ends by long ISIs
isi = diff(spikeTimes);

if ~isempty(spikeTimes)
isi = [spikeTimes(1) isi ];
end

% Look for a cluster with the biggest isi-- likely starts and ends
eva = evalclusters(isi','kmeans','DaviesBouldin','KList',1:3);
k = eva.OptimalK;

[labels, C] = kmeans(isi', k);

[~, idxMax] = max(C);
[~, idxMin] = min(C);

% Changes in isi (label as 1)
changes(labels ~= idxMin) = 1;

onlyAmp = 0;
% If you have too few or too many changes in time, also use amp changes
if sum(changes) > 500
    warning("Too many time changes initially detected")
    changes = zeros([1 length(spikeTimes)]); % too many = bad detection
    changes(labels == idxMax) = 1;
    useAmpChanges = 1;
    onlyAmp = 1;
end

if sum(changes) == 0 || length(spikeTimes) / sum(changes) > 10
    warning("Too few time changes initially detected")
    useAmpChanges = 1;
    onlyAmp = 1;
end

isChangeInISI = changes;

   
idxSpikes = int64(spikeTimes * Fs) + 1;
amp = v(idxSpikes);

%useAmpChanges = 0;

if useAmpChanges
    %% Look for changes in POS amplitude (helpful for back-to-back transitions like on PYN)
    % Look at nearby spikes time wise
    % If l - r is a large difference then probably transition
    %thresh = mean(abs(diff(amp)))  + (std(abs(diff(amp))));
    
    for i = 2:length(spikeTimes) - 1
        localIdx = abs(spikeTimes - spikeTimes(i)) < 5.0; % 5s local window
        localAmp = amp(localIdx);
        thresh = mean(abs(diff(localAmp))) + std(abs(diff(localAmp)));
        if sum(isChangeInISI(i - 1:i + 1)) > 0
            continue
        end
        localISI = median(isi(max(1,i-5):min(end,i+5)));
        dynamicWin = localISI * 8; % ~8 spikes worth of context
        closeSpikes = abs(spikeTimes - spikeTimes(i)) < dynamicWin;
        allIdx = 1:length(spikeTimes);
        idx = allIdx(closeSpikes);
        if isempty(idx(idx < i)) || isempty(idx(idx > i))
            continue
        end
        l = mean(amp(idx(idx < i)));
        r = mean(amp(idx(idx >= i)));
    
        if abs(l - r) > thresh        
            changes(i) = 1;
        end
    
    end
    
    %% Look for changes in NEG amplitude
    
    % Find the negative peak of each spike
    win = 3*10^-3; % Use a window size for shape of 3 ms;
    shapeSize = 2 * (win * Fs) + 1; % +1 for the spike itself 
    idxSpikes = int64(spikeTimes * Fs) + 1001;
    
    shape = zeros([length(idxSpikes) shapeSize]);
    
    tempV = [ zeros([1 1000]) v zeros([1 1000]) ];
    for i = 1:length(idxSpikes)
        shape(i, :) = tempV( (idxSpikes(i) - win*Fs ):(idxSpikes(i) + win*Fs) );
    end
    
    negAmp = min(shape, [], 2);
    
    
    for i = 2:length(spikeTimes) - 1
        localIdx = abs(spikeTimes - spikeTimes(i)) < 5.0; % 5s local window
        localAmp = amp(localIdx);
        thresh = mean(abs(diff(localAmp))) + std(abs(diff(localAmp)));
        if sum(isChangeInISI(i - 1:i + 1)) > 0
            continue
        end
        localISI = median(isi(max(1,i-5):min(end,i+5)));
        dynamicWin = localISI * 8; % ~8 spikes worth of context
        closeSpikes = abs(spikeTimes - spikeTimes(i)) < dynamicWin;
        allIdx = 1:length(spikeTimes);
        idx = allIdx(closeSpikes);

        if isempty(idx(idx < i)) || isempty(idx(idx > i))
            continue
        end
        l = mean(negAmp(idx(idx < i)));
        r = mean(negAmp(idx(idx >= i)));
    
        if abs(l - r) > thresh        
            changes(i) = 1;
        end
    
    end
    %% Group spikes that are changes in a row and find a separating point
    % Use changes only for plotting, use true changes for burst separation
    trueChanges = isChangeInISI; %zeros([1 length(spikeTimes)]);

    
    % Find where changes start (0 -> 1 on changes)
    changeStarts = zeros([1 length(spikeTimes)]);
    for i = 1:length(changes) - 1

        if changes(i) == 0 && changes(i + 1) == 1
            changeStarts(i + 1) = 1;
        end   
    
    end
    
    % ie, spikes from this point on are more similar to the following ones 
    idxChanges = find(changeStarts);
    for i = 1:length(idxChanges)
    
        currIdx = idxChanges(i);
        spikesToSplit = idxChanges(i);
        endGroup = 0;
        
        currIdx = currIdx + 1;
        while endGroup == 0 && currIdx <= length(spikeTimes)
            if changes(currIdx) == 1 
                spikesToSplit = [spikesToSplit currIdx];
                currIdx = currIdx + 1;
            else
                endGroup = 1;
            end
        end

    % Now that you have a group of spikes to split, look at their nearby
    % ones and find where is the strongest transition 

    % If there is one or more time transitions, then mark those as the only valid
    % transition
        if sum(isChangeInISI(spikesToSplit)) >= 1
        
            trueChanges(spikesToSplit(1):spikesToSplit(end)) = isChangeInISI(spikesToSplit);
        
        % Else find the biggest amplitude change from the left side
        % Look at positive and negative amplitude!
        else
        
            ampDiffPos = [];
            ampDiffNeg = [];
    
            bestScore = -Inf;
            bestSplit = spikesToSplit(1);
            for j = 1:length(spikesToSplit)
                splitPt = spikesToSplit(j);
                leftAmp = amp(max([1 splitPt - 4]):max([1 splitPt - 1]));
                rightAmp = amp(splitPt: min([length(amp) splitPt + 3]));
                if isempty(leftAmp) || isempty(rightAmp), continue; end
                    score = abs(mean(leftAmp) - mean(rightAmp));
                if score > bestScore
                    bestScore = score;
                    bestSplit = splitPt;
                end
            end
            trueChanges(bestSplit) = 1;
    
%             % Figure out if biggest amp diff is a positive or negative peak
%             if max(ampDiffPos) > max(ampDiffNeg)
%                 ampDiff = ampDiffPos;
%             else
%                 ampDiff = ampDiffNeg;
%             end
%             
%             [~, idxMaxAmpChange] = max(ampDiff);
%             ampDiff = 0 * ampDiff;
%             ampDiff(idxMaxAmpChange) = 1;
%             trueChanges(spikesToSplit(1):spikesToSplit(end)) = ampDiff;
        end


    end

    changes(trueChanges == 1) = 2;
else % only time changes wanted
    trueChanges = changes;
end
%% Figure
% figure
% gscatter(spikeTimes, amp, changes, [], [], 10)
% hold on
% t = (0:length(v) - 1) / Fs;
% plot(t, v, 'k-')

%% Wrap output up so you have easy access to burst number
spikeInfo = struct();

spikeInfo.spikeTimes = spikeTimes;
burstNum = zeros([length(spikeTimes) 1]);
currNum = 1;


for i = 1:length(trueChanges)
    if trueChanges(i)
        currNum = currNum + 1;
    end
    burstNum(i) = currNum;

end

spikeInfo.burstNum = burstNum;


    