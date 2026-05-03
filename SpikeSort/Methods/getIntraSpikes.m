function [spikes] = getIntraSpikes(v)
    % A bit more refined version of find peaks using clustering to help
    % partition what is or isn't true spikes, so we can avoid manually
    % thresholding!
    %%
    Fs = 10^4;
    

    time = 1/Fs * (0:length(v) - 1);
    [pks,locs,~,p] = findpeaks(v, time, "MinPeakDistance", .01, "MinPeakProminence",.5, "MinPeakHeight", mean(v) + 3);
    

    % Remove spikes from rig noise
    pks = pks(pks < 0);
    locs = locs(pks < 0);
    p = p(pks < 0);
    
    if isempty(pks)
        spikes = [];
        peak = pks;
    else

    % Cluster the data using peak height and prominence
    inputClustering = [];
    inputClustering(:, 1) = pks;
    inputClustering(:, 2) = p;


    %[labels, C] = kmeans(inputClustering, 2);
    
    % Minimum of five points needed
     labels = dbscan(inputClustering, 1, 5);

     % if num clusters < 2 recheck epsilon

 
     inputClustering = inputClustering(labels ~= -1, :);
     pks = pks(labels ~= -1);
     locs = locs(labels ~= -1);
     labels = labels(labels ~= -1);
     
     % if you only have one cluster assume it's everything
     if max(labels) == 1
         spikes = locs;
         peak = pks;

     % Merge centroids down to two clusters for intracellulars. one noise,
     % one spikes. only look at peak height here
     else
        C = splitapply(@mean,inputClustering,labels);
        

    
        [labelsK] = kmeans(C(:, 1), 2);
        newlabels = zeros([length(labels) 1]);
    
        for i = 1:length(labelsK)
            newlabels(labels == i) = labelsK(i);
        end
    
        labels = newlabels;
        
        % Fix to new centroids
        C = splitapply(@mean,inputClustering,labels);
     
        cluster1 = struct;
        cluster1.peak = C(1, 1);
        cluster1.prom = C(1, 2);
    
        cluster2 = struct;
        cluster2.peak = C(2, 1);
        cluster2.prom = C(2, 2);   
    
        % See if both clusters have similarly high peaks, or one is
        % just low level noise. Only return the cluster(s) that have true
        % spikes
    
        if cluster1.peak > cluster2.peak + 5
            % cluster one has higher peaks
            spikes = locs(labels == 1);
            peak = pks(labels == 1);
        elseif cluster2.peak > cluster1.peak + 5
            % cluster two has higher peaks
            spikes = locs(labels == 2);
            peak = pks(labels == 2);
    
        % peaks are either all spikes or all low oscillations
        elseif cluster1.prom > 3 && cluster2.prom > 3
            spikes = locs;
            peak = pks;
        else
            spikes = [];
            peak = [];
        end

     end

    % Finally, make sure to just remove any low peaks below std
    
    end

    stdev = std(peak);
    avg = mean(peak);

    idx = peak > avg - 3 * stdev;

    peak = peak(idx);
    spikes = spikes(idx);
    figure
    hold on
    plot(time, v);
    scatter(spikes, peak);
    title(length(peak) + " peaks detected")

    
    







    

