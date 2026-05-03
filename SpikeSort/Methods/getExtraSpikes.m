function [spikes] = getExtraSpikes(v, varargin)
    %% Detect extracellular spikes, and optionally use another neuron's spike times as a filter
   
    % getExtraSpikes(v)
    % getExtraSpikes(v, filterSpikes)

    % Inputs:
        % v (double []) - the voltage signal
        % filterSpikes - spike times of another neuron on v. dont return spikes
        % near these ones

    % Outputs:
        % spikes (double []) - detected spike times
    %%
    Fs = 10^4;
    
    time = 1/Fs * (0:length(v) - 1);
    %v = bandpass(v,[300 3000]); 
    [pks,locs,~,p] = findpeaks(v, time, "MinPeakDistance", .01, "MinPeakProminence",0.01);
    

    % If nothing detected or not bimodal bursting , return early
    if isempty(pks) 
        spikes = [];
        return
    end

    % Remove high spikes from rig noise

    idx = pks < 2;
    pks = pks(idx);
    locs = locs(idx);


    % Remove spikes overlapping from another neuron
    if nargin == 2
        filterSpikes = varargin{1};

        for i = filterSpikes
            locs(locs > i - 0.02 & locs< i + 0.02) = 0;
        end
    
        idx = find(locs);
        locs= locs(idx);
        pks = pks(idx);

    end 

    % Cluster the data using peak height and prominence
    inputClustering = [];
    inputClustering(:, 1) = pks;

    rng(1);
    eva = evalclusters(inputClustering,'kmeans','silhouette','KList',1:4);
    k = eva.OptimalK;
    [labels, C] = kmeans(inputClustering, k);
    
     [~, noiseCluster] = min(C);

     pks = pks(labels ~= noiseCluster);
     locs = locs(labels ~= noiseCluster);


    % Finally, make sure to just remove any low peaks below std

    stdev = std(pks);
    avg = mean(pks);

    idx = pks > avg - 3 * stdev;
    pks = pks(idx);
    locs = locs(idx);

%     figure
%     hold on
%     plot(time, v);
%     scatter(locs, pks);
%     title(length(pks) + " peaks detected")

    spikes = locs;
    







    

