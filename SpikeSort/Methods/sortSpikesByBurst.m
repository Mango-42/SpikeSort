function [spikeGroups, data] = sortSpikesByBurst(v, varargin)

    %% Description: Sorts spikes from two neurons given raw trace

    % Inputs:
        % v (double []): your recorded nerve trace

    % Optional args (paired):
        % spikeTimes (double[]): see below field
        % !
        % keep (bool): - 0 (filter above out) vs 1 (use these spikes)

        % sortOn (bool): 0 (don't sort, I only need the features) vs 1 (default)
        % !
        % livelabel (bool): - 0 (default) vs 1 (show and let me label my spike
            % groups in miniSpikesPipeline.m)
 

       % Valid signatures include
        % sortSpikes(v)
        % sortSpikes(v, spikeTimes, keep), 
        % sortSpikes(v, sortOn, livelabel), 
        % sortSpikes(v, spikeTimes, keep, sortOn, livelabel)

    % Outputs:
        % spikeGroups - use miniSpikesPipeline to label sequentially

        % data (2D double []): if you want access to the raw features for the spikes

    % Note these spike groups do not have names as there is no expected
    % neuron type. 

    % Method:

    % This function can run through getExtraSpikes.m to detect spikes first.

    % It sorts spikes by clustering them just using spike waveform


%% Get spike times and changes
 

    Fs = 10^4;
    win = 3*10^-3; % Use a window size for shape of 3 ms;
    shapeSize = 2 * (win * Fs) + 1; % +1 for the spike itself 
    
    sortOn = 1;
    livelabel = 0;
    
    if nargin == 1
        [spikeTimes] = getExtraSpikes(v); 
    
    % give spike times to filter by (keep on or off)
    elseif nargin >= 3 && length(varargin{1}) > 1 && varargin{2} == 0
        [spikeTimes] = getExtraSpikes(v, varargin{1});

    % give spike times to use
    elseif nargin >= 3 && length(varargin{1}) > 1 && varargin{2} == 1
        spikeTimes = varargin{1};
        
    end

    if nargin > 1 && length(varargin{1}) == 1
      [spikeTimes] = getExtraSpikes(v); 
      sortOn = varargin{1};
      livelabel = varargin{2};
    end

    if nargin > 3
      sortOn = varargin{3};
      livelabel = varargin{4};
    end

    v = reshape(v,[1,length(v)]);
    spikeTimes = reshape(spikeTimes,[1,length(spikeTimes)]);

    [spikeInfo] = findSpikeChanges(v, spikeTimes);
    if isempty(spikeTimes) || isempty(spikeInfo.burstNum)
        return
    end
    
    
%% Get spike and burst features
    oldV = v; % Make a copy of v
    
    % Add buffer around the sides so you can get window up to 100 ms
    v = [ zeros([1 1000]) v zeros([1 1000]) ];
    
    idxSpikes = int64(spikeTimes * Fs) + 1001;
    
    shape = [zeros([length(idxSpikes) shapeSize])];
    
    % Get shape of each spike and negative peak
    for i = 1:length(idxSpikes)
        shape(i, :) = v( (idxSpikes(i) - win*Fs ):(idxSpikes(i) + win*Fs) );
    end
    
    % Reduce shape into 2 dim TSNE
    smallShape = tsne(shape);
    % Features 1 & 2: Amplitude and Negative Amplitude
    amp = v(idxSpikes);
    negAmp = min(shape, [], 2);

    % Feature 3: Spike frequency ISI
    % Get ISI: Expand to have an "isi" for first and last spike
    isi = diff(spikeTimes);
   
    if ~isempty(spikeTimes)
    isi = [spikeTimes(1) isi length(oldV)/ Fs - spikeTimes(end)];
    end

    isiSmaller = [];
    isiLarger = [];

    % Make sure you're only using spike freq ISI, not burst freq
    for i = 1:length(spikeTimes)
        beforeIsi = isi(i);
        afterIsi = isi(i + 1);       
        isiSmaller(i) = min([beforeIsi afterIsi]);
        isiLarger(i) = max([beforeIsi afterIsi]);
    end

    % Burst Features
    neighborShape = zeros([length(spikeTimes) shapeSize]);
    neighborAmp = [zeros([length(spikeTimes) 1])];
    neighborNegAmp = [zeros([length(spikeTimes) 1])];
    neighborStdAmp = [zeros([length(spikeTimes) 1])];
    neighborStdNegAmp = [zeros([length(spikeTimes) 1])];
    neighborIsi = [zeros([length(spikeTimes) 1])];
    neighborStdIsi = [zeros([length(spikeTimes) 1])];
    numSpikes = [zeros([length(spikeTimes) 1])];
    neighborIsiMin = [zeros([length(spikeTimes) 1])];
    neighborIsiMax = [zeros([length(spikeTimes) 1])];
    burstTime = [zeros([length(spikeTimes) 1])];

    lastBurstStart = -1;
    lastBurstNum = 0;


    % Gather relevant burst stats for each spike
    for i = 1:length(spikeTimes)
    
       % Aberrant spikes
       if spikeInfo.burstNum(i) == -1
           numSpikes(i) = 1;
           simWave = shape(i);
           simAmp = amp(i);
           simNegAmp = negAmp(i);
           simStdAmp = 0;
           simStdNegAmp = 0;
           simIsi = isiSmaller(i);
           simStdIsi = 0;
           groupIsiMin = isiSmaller(i);
           groupIsiMax = isiLarger(i);
           burstTime(i) = 0;
    
       else
            % Find the 5 nearest spikes in the same burst (to account for
            % occasional poor burst detection pre-sorting)
            idx = find(spikeInfo.burstNum == spikeInfo.burstNum(i));
            numSpikes(i) = length(idx);
           
            distance = abs(spikeInfo.spikeTimes(idx) - spikeInfo.spikeTimes(i));
            
            % Get burst time only when new burst starts
            if spikeInfo.burstNum(i) ~= lastBurstNum
                burstTime(idx) = max(distance);
                lastBurstNum = spikeInfo.burstNum(i);
            end

            [~, idxMin] = sort(distance);
            idx = idx(idxMin <= 5);
            
            simWave = mean(shape(idx, :));
            simAmp = median(amp(idx));
            simStdAmp = std(amp(idx));
            simNegAmp = median(negAmp(idx));
            simStdNegAmp = std(negAmp(idx));
            simIsi = median(isiSmaller(idx));
            simStdIsi = std(isiSmaller(idx));
            groupIsiMin = min(isiSmaller(idx));
            groupIsiMax = max(isiSmaller(idx));
    
       end
       neighborShape(i, :) = simWave;
       neighborAmp(i) = simAmp;
       neighborStdAmp(i) = simStdAmp;
       neighborNegAmp(i) = simNegAmp;
       neighborStdNegAmp(i) = simStdNegAmp;
       neighborIsi(i) = simIsi;
       neighborStdIsi(i) = simStdIsi;
       neighborIsiMin(i) = groupIsiMin;
       neighborIsiMax(i) = groupIsiMax;
    
    end

    neighborShapeReduced = tsne(neighborShape);


    % Assemble collected spike info and mean info of spikes in the same burst
    % into a set for dim reduction
    data  = zeros([length(spikeTimes), 13]);%]);

    % Spike-specific features
    data(:, 1) = amp;
    data(:, 2) = negAmp;
    data(:, 3) = isiSmaller;
%     % Burst-specific features
    %data(:, 4) = numSpikes; % ignored after round 1
    %data(:, 5) = burstTime; % ignored after round 1
    data(:, 6) = neighborAmp;
    data(:, 7) = neighborStdAmp;
    data(:, 8) = neighborNegAmp;
    data(:, 9) = neighborStdNegAmp;
    data(:, 10) = neighborIsi;
    data(:, 11) = neighborStdIsi;
    data(:, 12) = neighborIsiMin;
    data(:, 5) = neighborIsiMax;
    % Reduced waveform
%     data(:, 1) = smallShape(:, 1);
%     data(:, 2) = smallShape(:, 2);
%     data(:, 3) = neighborShapeReduced(:, 1);
%     data(:, 4) = neighborShapeReduced(:, 2);



%% If you're not sorting, terminate early

if sortOn == 0
    spikeGroups = 0;
    return
end

    
 %% Cluster on dimensionality reduced data
   rng(1);
   reduced = tsne(data,'Standardize', 1); %, 'Standardize', 1
%    eva = evalclusters(reduced,'kmeans','DaviesBouldin','KList',1:3);
%    k = eva.OptimalK;
 %  [~, scores] = pca(data); %, 'Standardize', 1
 %  reduced = scores(:, 1:2);
    labels = kmeans(reduced, 5, 'Replicates', 5);

 %   labels = clusterdata(reduced, MaxClust = 6);

    %labels = kmeans(reduced, 2, 'Replicates', 5);



    %Label such that each burst has spikes of most common type
%        for i = 1:length(labels)
%                 
%                 idx = find(spikeInfo.burstNum == spikeInfo.burstNum(i));
%                 %distance = abs(spikeInfo.spikeTimes(idx) - spikeInfo.spikeTimes(i));
%                 %[~, idxMin] = sort(distance);
%                 %idx = idx(idxMin <= 5);
%     
%                 newLabel = mode(labels(idx));
%     
%      %      end
%            newLabels(i) = newLabel;
%            
%        end
%     
%        labels = newLabels;

%       gscatter(spikeTimes, amp, labels, [], [], 15)


%% Create a structure to hold spike times of different groups
spikeGroups = struct();
for i = 1:max(labels)
    spikeGroups.("spikeTimes" + i) = spikeTimes(labels == i);
    
end

% %Final figure
% figure
% v = oldV;
% t = (0:length(v) - 1) / Fs;
% 
% gscatter(spikeTimes, amp, labels, [], [], 15)
% hold on
% plot(t, v, 'k-')

% Projection, for debugging purposes

%  figure
%  gscatter(reduced(:, 1), reduced(:, 2), labels)


%% Give option to label each burst by max spike label (sometimes gets rid of noise)

if livelabel == 0
    return
end
prompt = "Label each burst by max label? Y/N ";
x = input(prompt, "s");

if x == "Y"

    %Label such that each burst has spikes of most common type
       for i = 1:length(labels)
                
                idx = find(spikeInfo.burstNum == spikeInfo.burstNum(i));
                %distance = abs(spikeInfo.spikeTimes(idx) - spikeInfo.spikeTimes(i));
                %[~, idxMin] = sort(distance);
                %idx = idx(idxMin <= 5);
    
                newLabel = mode(labels(idx));
    
     %      end
           newLabels(i) = newLabel;
           
       end
    
       labels = newLabels;

       gscatter(spikeTimes, amp, labels, [], [], 10)

end



%% Label groups 
prompt = "type neuron and its group number, i.e. LP 2: ";
x = "";

while x ~= "exit"

    x = input(prompt, "s");
    x = split(x);


    if x == "exit"
        break
    end
    
    allSpikes = [];
    for i = 2:length(x)
        allSpikes = [allSpikes spikeGroups.("spikeTimes" + x{i})];
        spikeGroups = rmfield(spikeGroups,"spikeTimes" + x{i});
        allSpikes = sort(allSpikes);
    end
    spikeGroups.(x{1}) = allSpikes;
end   






