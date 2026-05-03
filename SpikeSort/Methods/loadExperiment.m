function extracted_data = loadExperiment(targetNotebook, targetPage, range)


% Set filenumbers 
metadata = metadataMaster;
directory = pathfinder(targetNotebook, targetPage);

if nargin == 2 || isequal(range, "all")
    
    file_search = strcat(directory, '/', '*.abf'); % Find ABF files
    files = dir(file_search); % List ABF files
    files = 0:length(files) - 1;

elseif isequal(range, "roi")
    
    files = metadata(targetNotebook, targetPage).files;

elseif isequal(range, "continuousRamp")
    f = metadata(targetNotebook, targetPage).files;
    files = f(1):f(end);

elseif isequal(range, "crash")

    [~, idxMax] = max(metadata(targetNotebook, targetPage).tempValues);
    fileCrash = metadata(targetNotebook, targetPage).files(idxMax);
    fileBefore = fileCrash - 2;
    files = fileBefore:fileCrash;
    
else 
    files = range;
end

files
% Initialize storage
Data = cell(1, length(files)); % Pre-allocate for efficiency
%file_names = cell(1, length(files));


% Load ABF files
for i = 1:length(files)

    numFile = files(i);
    %file_names{i} = files(i).name;
    %fullfile_name = fullfile(directory, file_names{i})
    
    filename = sprintf('%s%d_%03d_%04d.abf', directory, targetNotebook, targetPage, numFile);

    try
        [~, ~, fields_for_names] = abfload(filename, 'info');% Get ABF file info- channel names, etc

        [raw_data, ~, h] = abfload(filename); % Load ABF file data 
        Data{i} = raw_data';  % Ensure correct orientation: Channels x Samples

    catch
        warning('Could not load file: %s', filename);
    end
end

% Get recorded channel names
[~, ~, fields_for_names] = abfload(filename, 'info');
recorded_channels = fields_for_names.recChNames;

% Define possible cell types
cell_types = { 'PD','LP', 'LPG', 'GM', 'VD', 'PY', ...
    'lvn', 'pdn','lpn','llvn','ulvn', 'pyn',   'mvn', 'temp', 'lgn' ...
    'heart', 'Temp', 'p1', 'cpv4', 'gm5b', 'p2', 'gm6', 'cpv6', 'gm5a', 'cpv1a'...
    'force'};

% Initialize extracted data structure
extracted_data = struct();

% Loop through all possible cell types
for i = 1:length(cell_types)
    cell_type = cell_types{i};

    % Check if the metadata field exists and is non-empty
    if isfield(metadata(targetNotebook, targetPage).channels, cell_type) && ~isempty(metadata(targetNotebook, targetPage).channels.(cell_type))
        channel_name = metadata(targetNotebook, targetPage).channels.(cell_type);

        % Find index of the corresponding channel in recorded data
        channel_idx = find(strcmp(recorded_channels, channel_name));

        if ~isempty(channel_idx)
            % Extract and store full channel data for each file
            extracted_data.(cell_type) = cellfun(@(x) x(channel_idx, :), Data, 'UniformOutput', false);
        else
            warning('Channel %s not found in recorded data', channel_name);
        end
    end
end



end